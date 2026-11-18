import AAMServices
import AAMStorages
import AANModels
import Foundation

struct SynchronizeHealthMetric: Sendable {
  private struct Query {
    let start: Date
    let generation: UUID
    let anchor: Data?
    let reusableIDs: Set<UUID>
  }

  let source: any AppleHealthReading
  let store: HealthHistoryStore
  let interval: DateInterval

  func callAsFunction(
    _ metric: TodayHealthMetric,
    authorizationStart: Date?,
    deferredDate: Date?
  ) async throws -> Date? {
    let queryStart = max(interval.start, authorizationStart ?? interval.start)
    let retainingFrom = min(queryStart, interval.end)
    let window = DateInterval(start: retainingFrom, end: interval.end)
    if let checkpoint = try await store.checkpoint(for: metric),
       checkpoint.isVerified,
       checkpoint.queryStart <= queryStart,
       deferredDate.map({ $0 >= interval.end }) ?? true,
       authorizationStart.map({ $0 <= checkpoint.queryStart }) ?? true
    {
      do {
        let nextDeferred = try await drain(metric, retainingIn: window, query: Query(
          start: checkpoint.queryStart,
          generation: checkpoint.generation,
          anchor: checkpoint.anchor,
          reusableIDs: []
        ))
        try await store.prune(for: metric, retainingIn: window, generation: checkpoint.generation)
        return [deferredDate, nextDeferred].compactMap(\.self).min()
      } catch AppleHealthError.invalidAnchor {
        // A fresh enumeration closes the gap if the HealthKit cursor no longer works.
      }
    }

    let reconciliation = try await store.beginReconciliation(
      for: metric,
      retainingFrom: retainingFrom,
      queryStart: queryStart
    )
    let nextDeferred = try await drain(metric, retainingIn: window, query: Query(
      start: queryStart,
      generation: reconciliation.generation,
      anchor: nil,
      reusableIDs: reconciliation.reusableSampleIDs
    ))
    try await store.finishReconciliation(for: metric, generation: reconciliation.generation, retainingIn: window)
    return nextDeferred
  }

  private func drain(
    _ metric: TodayHealthMetric,
    retainingIn window: DateInterval,
    query: Query
  ) async throws -> Date? {
    var cursor = query.anchor
    var deferredDate: Date?
    while true {
      try Task.checkCancellation()
      let batch = try await source.sampleChanges(
        for: metric,
        since: query.start,
        anchor: cursor,
        reusing: query.reusableIDs
      )
      let drained = batch.seenSampleIDs.isEmpty && batch.deletedSampleIDs.isEmpty
      guard drained || batch.anchor != cursor else { throw AppleHealthError.queryFailed }
      try await store.apply(
        batch,
        for: metric,
        generation: query.generation,
        expectedAnchor: cursor,
        retainingIn: window
      )
      // Re-enumerate when a previously excluded future-dated measurement enters the window.
      if let nextDeferred = batch.measurements.lazy.map(\.endDate).filter({ $0 >= window.end }).min() {
        deferredDate = min(deferredDate ?? nextDeferred, nextDeferred)
      }
      if drained {
        return deferredDate
      }
      cursor = batch.anchor
    }
  }
}
