import AAMServices
import AANModels
import Foundation

public struct RefreshTodayHealth: Sendable {
  public enum Update: Sendable {
    case needsAuthorization
    case unavailable
    case restricted
    case failed
    case readingMeasurements
    case sleepNeedsAuthorization
    case sleep(TodaySleepSummary?)
    case sleepFailed
    case measurement(TodayHealthMetric, Reading, verification: UUID)
  }

  public enum Reading: Sendable {
    case empty
    case heartRate(HeartRateSummary)
    case bloodOxygen(BloodOxygenSample)
    case respiratoryRate(RespiratoryRateSample)
    case restingHeartRate(RestingHeartRateSample?, assessment: TodayBaselineAssessment)
    case heartRateVariability(HeartRateVariabilitySample?, assessment: TodayBaselineAssessment)
    case failed
  }

  private let prepareRead: PrepareHealthHistoryRead
  private let appleHealth: any AppleHealthReading
  private let synchronizeHealthHistory: SynchronizeHealthHistory

  public init(appleHealth: any AppleHealthReading, synchronizeHealthHistory: SynchronizeHealthHistory) {
    prepareRead = PrepareHealthHistoryRead(appleHealth: appleHealth, synchronizeHealthHistory: synchronizeHealthHistory)
    self.appleHealth = appleHealth
    self.synchronizeHealthHistory = synchronizeHealthHistory
  }

  /// Projects the selected time interval directly from the verified measurements backing the card.
  public func readTimeline(
    for metric: TodayHealthMetric,
    in interval: DateInterval,
    verification: UUID
  ) async throws -> [IntradayHealthPoint] {
    try await synchronizeHealthHistory.readTimeline(for: metric, in: interval, verification: verification)
  }

  /// Deliver incremental updates and check the caller's refresh identity on the same actor.
  @MainActor public func callAsFunction(
    requesting scope: AppleHealthReadScope? = nil,
    reusingLatest: Bool = false,
    isCurrent: @MainActor () -> Bool,
    onUpdate: @MainActor (Update) -> Void
  ) async {
    guard !Task.isCancelled, isCurrent() else { return }
    let historyAuthorization = scope == .sleep ? nil : scope
    let status = await prepareRead(requesting: historyAuthorization)
    guard !Task.isCancelled, isCurrent() else { return }
    if let update = authorizationUpdate(for: status) {
      onUpdate(update)
      return
    }
    guard status == .ready else { return }

    onUpdate(.readingMeasurements)
    async let sleep: Void = refreshSleep(
      requestAuthorization: scope == .sleep, isCurrent: isCurrent, onUpdate: onUpdate
    )
    let (generation, updates) = await synchronizeHealthHistory.verifiedUpdates(
      reusingLatest: reusingLatest && historyAuthorization == nil
    )
    for await update in updates {
      guard !Task.isCancelled, isCurrent() else { return }
      onUpdate(.measurement(update.metric, update.reading, verification: generation))
    }
    await sleep
    guard !Task.isCancelled, isCurrent() else { return }
    if scope != nil {
      await synchronizeHealthHistory.notifyVerifiedUpdate(generation)
    }
  }

  @MainActor private func refreshSleep(
    requestAuthorization: Bool,
    isCurrent: @MainActor () -> Bool,
    onUpdate: @MainActor (Update) -> Void
  ) async {
    let update: Update
    do {
      if requestAuthorization {
        try await appleHealth.requestReadAuthorization(for: .sleep)
      }
      if try await appleHealth.needsAuthorizationRequest(for: .sleep) {
        update = .sleepNeedsAuthorization
      } else {
        let summary = try await ReadTodaySleep(appleHealth: appleHealth)(now: .now, calendar: .current)
        update = .sleep(summary)
      }
    } catch is CancellationError where requestAuthorization {
      update = .sleepNeedsAuthorization
    } catch {
      update = .sleepFailed
    }
    guard !Task.isCancelled, isCurrent() else { return }
    onUpdate(update)
  }

  private func authorizationUpdate(for status: PrepareHealthHistoryRead.Status) -> Update? {
    switch status {
    case .ready, .cancelled: nil
    case .needsAuthorization: .needsAuthorization
    case .unavailable: .unavailable
    case .restricted: .restricted
    case .failed: .failed
    }
  }
}
