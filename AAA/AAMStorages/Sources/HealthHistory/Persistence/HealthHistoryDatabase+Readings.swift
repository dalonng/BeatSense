import AANModels
import Foundation
import SwiftData

extension HealthHistoryDatabase {
  private typealias Baseline = HealthHistorySchemaV1.Baseline

  func readings(
    for metric: TodayHealthMetric,
    in interval: DateInterval,
    limit: Int?,
    offset: Int
  ) throws -> [HealthMeasurement] {
    _ = try verifiedState(for: metric)
    return try fetchReadings(for: metric, in: interval, limit: limit, offset: offset)
  }

  func reduceReadings<Result: Sendable>(
    for metric: TodayHealthMetric,
    in interval: DateInterval,
    into initial: Result,
    _ accumulate: @Sendable (inout Result, HealthMeasurement) throws -> Void
  ) throws -> Result {
    try Task.checkCancellation()
    _ = try verifiedState(for: metric)
    var result = initial
    try modelContext.enumerate(readingsDescriptor(for: metric, in: interval), batchSize: 512) { stored in
      try Task.checkCancellation()
      try accumulate(&result, stored.measurement(for: metric))
    }
    return result
  }

  func baselineInput(for metric: TodayHealthMetric, in interval: DateInterval) throws -> HealthHistoryStore
    .BaselineInput
  {
    let state = try verifiedState(for: metric)
    let stored = try storedBaseline(for: metric)
    let matchesRevision = stored?.inputRevision == state.inputRevision
    return try .init(
      generation: state.generation,
      revision: state.inputRevision,
      measurements: fetchReadings(for: metric, in: interval, limit: nil, offset: 0),
      baseline: matchesRevision ? stored?.value : nil,
      previousHRVReference: metric == .heartRateVariability && !matchesRevision ? stored?.value : nil
    )
  }

  func personalBaseline(
    for metric: TodayHealthMetric,
    window: DateInterval,
    timeZoneID: String,
    algorithmVersion: Int
  ) throws -> PersonalBaseline? {
    let state = try verifiedState(for: metric)
    guard let baseline = try baseline(for: metric, revision: state.inputRevision),
          baseline.windowStart == window.start, baseline.windowEnd == window.end,
          baseline.timeZoneID == timeZoneID, baseline.algorithmVersion == algorithmVersion
    else {
      return nil
    }
    return baseline
  }

  func saveBaseline(
    _ baseline: PersonalBaseline,
    for metric: TodayHealthMetric,
    expectedGeneration: UUID,
    expectedRevision: UUID
  ) throws -> Bool {
    try Task.checkCancellation()
    guard isVerified(metric), let state = try state(for: metric),
          state.generation == expectedGeneration, state.inputRevision == expectedRevision
    else {
      return false
    }
    let stored = try storedBaseline(for: metric)
    try commit {
      if let stored {
        stored.update(from: baseline, revision: expectedRevision)
      } else {
        modelContext.insert(Baseline(metric: metric, baseline: baseline, revision: expectedRevision))
      }
    }
    return true
  }

  private func fetchReadings(
    for metric: TodayHealthMetric,
    in interval: DateInterval,
    limit: Int?,
    offset: Int
  ) throws -> [HealthMeasurement] {
    guard limit.map({ $0 > 0 }) ?? true, interval.duration > 0 else { return [] }
    var descriptor = readingsDescriptor(for: metric, in: interval)
    descriptor.fetchLimit = limit
    descriptor.fetchOffset = max(0, offset)
    return try modelContext.fetch(descriptor).map { $0.measurement(for: metric) }
  }

  private func readingsDescriptor(
    for metric: TodayHealthMetric,
    in interval: DateInterval
  ) -> FetchDescriptor<Measurement> {
    let metricCode = metric.rawValue
    let start = interval.start
    let end = interval.end
    return FetchDescriptor(
      predicate: #Predicate { $0.metricCode == metricCode && $0.endDate >= start && $0.endDate < end },
      sortBy: [SortDescriptor(\.endDate, order: .reverse), SortDescriptor(\.healthKitUUID), SortDescriptor(\.ordinal)]
    )
  }

  private func baseline(for metric: TodayHealthMetric, revision: UUID) throws -> PersonalBaseline? {
    guard let baseline = try storedBaseline(for: metric), baseline.inputRevision == revision else { return nil }
    return baseline.value
  }

  private func storedBaseline(for metric: TodayHealthMetric) throws -> Baseline? {
    let metricCode = metric.rawValue
    var descriptor = FetchDescriptor<Baseline>(predicate: #Predicate { $0.metricCode == metricCode })
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }

  func invalidateBaseline(for metric: TodayHealthMetric, state: SyncState) throws {
    let previousRevision = state.inputRevision
    state.inputRevision = UUID()
    guard let previous = try storedBaseline(for: metric) else { return }
    // An established HRV window can survive a new batch. Revalidate it against
    // the remaining samples before using it, and discard the old statistics now.
    guard metric == .heartRateVariability, let source = previous.sourceIdentifier, previous.referencePeriod != nil,
          previous.p50 != nil || previous.inputRevision != previousRevision
    else {
      modelContext.delete(previous)
      return
    }
    let code = metric.rawValue
    let device = previous.deviceIdentifier
    let remaining = FetchDescriptor<Measurement>(predicate: #Predicate {
      $0.metricCode == code && $0.sourceIdentifier == source && $0.deviceIdentifier == device
    })
    guard try modelContext.fetchCount(remaining) > 0 else {
      modelContext.delete(previous)
      return
    }
    previous.p10 = nil
    previous.p50 = nil
    previous.p90 = nil
    previous.validDayCount = 0
  }
}
