import AANModels
import Foundation
import SwiftData

@ModelActor
actor HealthHistoryDatabase {
  typealias Measurement = HealthHistorySchemaV1.Measurement
  typealias SyncState = HealthHistorySchemaV1.SyncState
  private typealias StoreError = HealthHistoryStore.StoreError

  private struct ReconciliationProgress {
    var unseenSampleIDs: Set<UUID>
    var exhausted = false
  }

  private var activeGenerations: [TodayHealthMetric: UUID] = [:]
  private var reconciliations: [TodayHealthMetric: ReconciliationProgress] = [:]

  func beginReconciliation(
    for metric: TodayHealthMetric,
    retainingFrom cutoff: Date,
    queryStart: Date
  ) throws -> HealthHistoryStore.Reconciliation {
    try Task.checkCancellation()
    invalidateVerification(for: metric)
    let generation = UUID()
    let previous = try state(for: metric)
    let canReuse = previous?.completedCutoff.map { cutoff >= $0 } ?? false
    let sampleIDs = try previousSampleIDs(for: metric, retainingFrom: cutoff, canReuse: canReuse)

    try commit {
      if let previous {
        previous.generation = generation
        previous.anchor = nil
        previous.queryStart = queryStart
        previous.completedCutoff = nil
      } else {
        modelContext.insert(SyncState(metric: metric, generation: generation, queryStart: queryStart))
      }
    }
    activeGenerations[metric] = generation
    reconciliations[metric] = ReconciliationProgress(unseenSampleIDs: sampleIDs.all)
    return .init(generation: generation, reusableSampleIDs: sampleIDs.reusable)
  }

  func apply(
    _ batch: HealthSampleBatch,
    for metric: TodayHealthMetric,
    generation: UUID,
    expectedAnchor: Data?,
    retainingIn interval: DateInterval
  ) throws {
    try Task.checkCancellation()
    let state = try activeState(for: metric, generation: generation)
    guard state.anchor == expectedAnchor else { throw StoreError.superseded }
    let seen = Set(batch.seenSampleIDs)
    let deleted = Set(batch.deletedSampleIDs)
    let samples = Dictionary(grouping: batch.measurements, by: \.healthKitUUID)
    try validate(samples, seen: seen, metric: metric)
    let rows = try rows(for: metric, sampleIDs: deleted.union(samples.keys))
    let rowsBySample = Dictionary(grouping: rows, by: \.healthKitUUID)

    try commit {
      var changed = false
      for id in deleted {
        for row in rowsBySample[id, default: []] {
          modelContext.delete(row)
          changed = true
        }
      }
      for (id, measurements) in samples where !deleted.contains(id) {
        let existing = rowsBySample[id, default: []]
        if replace(existing, with: measurements, retainingIn: interval) {
          changed = true
        }
      }
      if let completedCutoff = state.completedCutoff, completedCutoff < interval.start {
        state.completedCutoff = interval.start
      }
      if state.anchor != batch.anchor {
        state.anchor = batch.anchor
      }
      if changed {
        try invalidateBaseline(for: metric, state: state)
      }
    }
    reconciliations[metric]?.unseenSampleIDs.subtract(seen)
    reconciliations[metric]?.unseenSampleIDs.subtract(deleted)
    reconciliations[metric]?.exhausted = seen.isEmpty && deleted.isEmpty
  }

  func finishReconciliation(
    for metric: TodayHealthMetric,
    generation: UUID,
    retainingIn interval: DateInterval
  ) throws {
    try Task.checkCancellation()
    let state = try activeState(for: metric, generation: generation)
    guard let progress = reconciliations[metric], progress.exhausted else {
      throw StoreError.incompleteReconciliation
    }
    let expired = try expiredRows(for: metric, retainingIn: interval)
    let invisible = try rows(for: metric, sampleIDs: progress.unseenSampleIDs)
    let didClipFuture = expired.contains { $0.endDate >= interval.end }
    try updateRetention(
      state,
      for: metric,
      cutoff: didClipFuture ? nil : interval.start,
      removing: Set(expired).union(invisible)
    )
    reconciliations.removeValue(forKey: metric)
  }

  func checkpoint(for metric: TodayHealthMetric) throws -> HealthHistoryStore.Checkpoint? {
    try Task.checkCancellation()
    guard let state = try state(for: metric) else { return nil }
    return .init(
      generation: state.generation,
      anchor: state.anchor,
      queryStart: state.queryStart,
      isVerified: isVerified(metric)
    )
  }

  func invalidateVerification(for metric: TodayHealthMetric?) {
    guard !Task.isCancelled else { return }
    if let metric {
      reconciliations.removeValue(forKey: metric)
      activeGenerations.removeValue(forKey: metric)
    } else {
      reconciliations.removeAll()
      activeGenerations.removeAll()
    }
  }

  private func replace(
    _ existing: [Measurement],
    with measurements: [HealthMeasurement],
    retainingIn interval: DateInterval
  ) -> Bool {
    var remaining = Dictionary(uniqueKeysWithValues: existing.map { ($0.ordinal, $0) })
    // Any entries beyond this scan's upper bound need another series read on a later reconciliation.
    let canReuse = measurements.allSatisfy { $0.endDate < interval.end }
    var changed = false
    for sample in measurements where sample.endDate >= interval.start && sample.endDate < interval.end {
      if let row = remaining.removeValue(forKey: sample.ordinal) {
        if row.measurement(for: sample.metric) != sample {
          row.update(from: sample)
          changed = true
        }
        if row.canReuse != canReuse {
          row.canReuse = canReuse
        }
      } else {
        modelContext.insert(Measurement(sample, canReuse: canReuse))
        changed = true
      }
    }
    remaining.values.forEach { modelContext.delete($0) }
    return changed || !remaining.isEmpty
  }

  private func validate(
    _ groups: [UUID: [HealthMeasurement]],
    seen: Set<UUID>,
    metric: TodayHealthMetric
  ) throws {
    for (id, samples) in groups {
      var ordinals = Set<Int>()
      guard seen.contains(id), samples.allSatisfy({ sample in
        sample.metric == metric && sample.ordinal >= 0 && sample.value.isFinite
          && sample.startDate.timeIntervalSinceReferenceDate.isFinite && sample.endDate.timeIntervalSinceReferenceDate
          .isFinite
          && sample.startDate <= sample.endDate && ordinals.insert(sample.ordinal).inserted
      }) else {
        throw StoreError.invalidBatch
      }
    }
  }

  private func previousSampleIDs(
    for metric: TodayHealthMetric,
    retainingFrom cutoff: Date,
    canReuse: Bool
  ) throws -> (all: Set<UUID>, reusable: Set<UUID>) {
    let metricCode = metric.rawValue
    let descriptor = FetchDescriptor<Measurement>(predicate: #Predicate { $0.metricCode == metricCode })
    var all = Set<UUID>()
    var reusable = Set<UUID>()
    try modelContext.enumerate(descriptor, batchSize: 500) { row in
      try Task.checkCancellation()
      all.insert(row.healthKitUUID)
      if canReuse, row.canReuse, row.endDate >= cutoff {
        reusable.insert(row.healthKitUUID)
      }
    }
    return (all, reusable)
  }

  private func rows(for metric: TodayHealthMetric, sampleIDs: Set<UUID>) throws -> [Measurement] {
    guard !sampleIDs.isEmpty else { return [] }
    let metricCode = metric.rawValue
    let all = Array(sampleIDs)
    var rows: [Measurement] = []
    for start in stride(from: 0, to: all.count, by: 300) {
      try Task.checkCancellation()
      let ids = Array(all[start ..< min(start + 300, all.count)])
      rows += try modelContext.fetch(FetchDescriptor<Measurement>(predicate: #Predicate {
        $0.metricCode == metricCode && ids.contains($0.healthKitUUID)
      }))
    }
    return rows
  }

  func activeState(for metric: TodayHealthMetric, generation: UUID) throws -> SyncState {
    guard activeGenerations[metric] == generation,
          let state = try state(for: metric), state.generation == generation
    else {
      throw StoreError.superseded
    }
    return state
  }

  func verifiedState(for metric: TodayHealthMetric) throws -> SyncState {
    try Task.checkCancellation()
    guard isVerified(metric), let state = try state(for: metric) else {
      throw StoreError.unverified
    }
    return state
  }

  func isVerified(_ metric: TodayHealthMetric) -> Bool {
    activeGenerations[metric] != nil && reconciliations[metric] == nil
  }

  func state(for metric: TodayHealthMetric) throws -> SyncState? {
    let metricCode = metric.rawValue
    var descriptor = FetchDescriptor<SyncState>(predicate: #Predicate { $0.metricCode == metricCode })
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }

  func commit(_ mutate: () throws -> Void) throws {
    do {
      try mutate()
      try Task.checkCancellation()
      if modelContext.hasChanges {
        try modelContext.save()
      }
    } catch {
      modelContext.rollback()
      throw error
    }
  }
}
