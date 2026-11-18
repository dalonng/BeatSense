import AAMServices
import AANModels
import Foundation
import OSLog

public struct RefreshHealthTrends: Sendable {
  public enum Series: Equatable, Sendable {
    case readings([DailyHealthValue])
    case failed
  }

  public struct Snapshot: Equatable, Sendable {
    public let interval: DateInterval
    public let calendar: Calendar
    public let series: [TodayHealthMetric: Series]
    public let baselines: [TodayHealthMetric: HealthBaselineRange]
  }

  public enum LoadError: Error, Equatable, Sendable {
    case needsAuthorization
    case unavailable
    case restricted
    case failed
  }

  private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BeatSense", category: "HealthTrends")
  private let prepareRead: PrepareHealthHistoryRead
  private let synchronizeHealthHistory: SynchronizeHealthHistory

  public init(appleHealth: any AppleHealthReading, synchronizeHealthHistory: SynchronizeHealthHistory) {
    prepareRead = PrepareHealthHistoryRead(appleHealth: appleHealth, synchronizeHealthHistory: synchronizeHealthHistory)
    self.synchronizeHealthHistory = synchronizeHealthHistory
  }

  public func callAsFunction(
    requestAuthorization: Bool = false,
    reusingLatest: Bool = false,
    retentionDays: Int? = nil
  ) async throws -> Snapshot {
    try await checkReadAccess(requestAuthorization: requestAuthorization)
    let (generation, updates) = await synchronizeHealthHistory.verifiedUpdates(
      reusingLatest: reusingLatest && !requestAuthorization
    )
    var synchronized: [TodayHealthMetric: SynchronizeHealthHistory.Update] = [:]
    for await update in updates {
      synchronized[update.metric] = update
    }
    try Task.checkCancellation()
    if requestAuthorization {
      await synchronizeHealthHistory.notifyVerifiedUpdate(generation)
    }

    guard await synchronizeHealthHistory.isCurrentVerification(generation),
          synchronized.count == TodayHealthMetric.allCases.count,
          let projection = ReadDailyHealthTrend(now: .now, calendar: .current, retentionDays: retentionDays)
    else { throw LoadError.failed }

    let series = try await collectSeries(for: synchronized, using: projection)
    try Task.checkCancellation()
    guard let verifiedRetention = await synchronizeHealthHistory.verifiedRetentionDays(for: generation)
    else { throw LoadError.failed }
    // The chart query already applies a shorter selection while the shared mirror catches up.
    let baselines = if retentionDays.map({ $0 < verifiedRetention }) == true {
      [TodayHealthMetric: HealthBaselineRange]()
    } else {
      collectBaselines(for: synchronized, series: series, using: projection)
    }
    return Snapshot(interval: projection.interval, calendar: projection.calendar, series: series, baselines: baselines)
  }

  private func checkReadAccess(requestAuthorization: Bool) async throws {
    let status = await prepareRead(requesting: requestAuthorization ? .measurements : nil)
    try Task.checkCancellation()
    switch status {
    case .ready: break
    case .needsAuthorization: throw LoadError.needsAuthorization
    case .unavailable: throw LoadError.unavailable
    case .restricted: throw LoadError.restricted
    case .failed: throw LoadError.failed
    case .cancelled: throw CancellationError()
    }
  }

  private func collectSeries(
    for synchronized: [TodayHealthMetric: SynchronizeHealthHistory.Update],
    using projection: ReadDailyHealthTrend
  ) async throws -> [TodayHealthMetric: Series] {
    try await withThrowingTaskGroup(of: (TodayHealthMetric, Series).self) { group in
      for (metric, update) in synchronized {
        group.addTask {
          if case .failed = update.reading {
            return (metric, .failed)
          }
          do {
            return try await (metric, .readings(synchronizeHealthHistory.readTrend(for: metric, using: projection)))
          } catch {
            try Task.checkCancellation()
            let code = (error as NSError).code
            Self.logger
              .error(
                "Trend range read failed for \(metric.rawValue, privacy: .public), code \(code, privacy: .public)."
              )
            return (metric, .failed)
          }
        }
      }
      var readings: [TodayHealthMetric: Series] = [:]
      for try await (metric, result) in group {
        readings[metric] = result
      }
      return readings
    }
  }

  private func collectBaselines(
    for synchronized: [TodayHealthMetric: SynchronizeHealthHistory.Update],
    series: [TodayHealthMetric: Series],
    using projection: ReadDailyHealthTrend
  ) -> [TodayHealthMetric: HealthBaselineRange] {
    synchronized.compactMapValues { update in
      guard case .readings? = series[update.metric],
            let baseline = update.baseline,
            baseline.day == projection.todayStart,
            baseline.timeZoneID == projection.calendar.timeZone.identifier else { return nil }
      return baseline.range
    }
  }
}
