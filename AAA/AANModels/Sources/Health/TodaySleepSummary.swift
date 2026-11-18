import Foundation

/// The first and last recorded sleep and the time actually asleep within that session.
public struct TodaySleepSummary: Equatable, Sendable {
  public let startDate: Date
  public let endDate: Date
  /// Observed seconds within the session. Conflicting sleep stages count as unspecified sleep.
  /// A missing key means this stage has no attributable duration in the visible samples.
  public let stageDurations: [SleepSample.State: TimeInterval]

  public var asleepDuration: TimeInterval {
    (stageDurations[.asleep] ?? 0) + (stageDurations[.core] ?? 0) +
      (stageDurations[.deep] ?? 0) + (stageDurations[.rem] ?? 0)
  }

  public init(startDate: Date, endDate: Date, stageDurations: [SleepSample.State: TimeInterval]) {
    self.startDate = startDate
    self.endDate = endDate
    self.stageDurations = stageDurations
  }
}
