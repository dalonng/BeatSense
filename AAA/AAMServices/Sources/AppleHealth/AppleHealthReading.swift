import AANModels
import Foundation

public enum AppleHealthReadScope: Sendable {
  case measurements
  case sleep
  case all
}

public protocol AppleHealthReading: Sendable {
  /// Whether the system would show the read authorization sheet for the requested types.
  func needsAuthorizationRequest(for scope: AppleHealthReadScope) async throws -> Bool

  /// Requests read access. Completion does not indicate whether access was granted.
  func requestReadAuthorization(for scope: AppleHealthReadScope) async throws

  /// Observes sample changes for the lifetime of `consume`. Cancellation stops observation.
  func observeSampleChanges(_ consume: @Sendable (AsyncStream<Void>) async -> Void) async throws

  /// Returns visible asleep and awake samples overlapping the window with their original endpoints.
  func sleepSamples(in interval: DateInterval) async throws -> [SleepSample]

  /// Returns a page for a stable lower bound. Both ID lists are empty when caught up.
  /// Pass reusable IDs only for immutable parents fully imported for this lower bound.
  func sampleChanges(
    for metric: TodayHealthMetric,
    since start: Date,
    anchor: Data?,
    reusing sampleIDs: Set<UUID>
  ) async throws -> HealthSampleBatch

  /// Missing entries represent an unknown read scope. Only limited access reports a date.
  func earliestAuthorizedSampleDates() async throws -> [TodayHealthMetric: Date]
}
