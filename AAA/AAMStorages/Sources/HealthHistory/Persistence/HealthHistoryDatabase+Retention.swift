import AANModels
import Foundation
import SwiftData

extension HealthHistoryDatabase {
  func prune(for metric: TodayHealthMetric, retainingIn interval: DateInterval, generation: UUID) throws {
    try Task.checkCancellation()
    let state = try activeState(for: metric, generation: generation)
    guard isVerified(metric) else { throw HealthHistoryStore.StoreError.unverified }
    let expired = try expiredRows(for: metric, retainingIn: interval)
    let cutoff = state.completedCutoff.map { max($0, interval.start) }
    let didClipFuture = expired.contains { $0.endDate >= interval.end }
    try updateRetention(state, for: metric, cutoff: didClipFuture ? nil : cutoff, removing: expired)
  }

  func pruneExpired(before cutoff: Date) throws {
    for metric in TodayHealthMetric.allCases {
      try Task.checkCancellation()
      guard let state = try state(for: metric) else { continue }
      let metricCode = metric.rawValue
      let expired = try modelContext.fetch(FetchDescriptor<Measurement>(predicate: #Predicate {
        $0.metricCode == metricCode && $0.endDate < cutoff
      }))
      guard !expired.isEmpty else { continue }
      let retainedStart = state.completedCutoff.map { max($0, cutoff) }
      try updateRetention(state, for: metric, cutoff: retainedStart, removing: expired)
    }
  }

  func updateRetention(
    _ state: SyncState,
    for metric: TodayHealthMetric,
    cutoff: Date?,
    removing stale: some Collection<Measurement>
  ) throws {
    try commit {
      if state.completedCutoff != cutoff {
        state.completedCutoff = cutoff
      }
      stale.forEach { modelContext.delete($0) }
      if !stale.isEmpty {
        try invalidateBaseline(for: metric, state: state)
      }
    }
  }

  func expiredRows(for metric: TodayHealthMetric, retainingIn interval: DateInterval) throws -> [Measurement] {
    let metricCode = metric.rawValue
    let start = interval.start
    let end = interval.end
    return try modelContext.fetch(FetchDescriptor<Measurement>(predicate: #Predicate {
      $0.metricCode == metricCode && ($0.endDate < start || $0.endDate >= end)
    }))
  }
}
