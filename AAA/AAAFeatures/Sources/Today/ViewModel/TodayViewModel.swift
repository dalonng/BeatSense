import AACUseCases
import AAMServices
import AANModels
import Foundation
import Observation

@MainActor
@Observable
final class TodayViewModel {
  enum Phase: Equatable {
    case loading
    case needsConnection
    case unavailable
    case restricted
    case ready
    case failed
  }

  enum SleepState: Equatable {
    case loading
    case needsConnection
    case empty
    case summary(TodaySleepSummary)
    case failed
  }

  enum MeasurementState: Equatable, Sendable {
    case loading
    case empty
    case sample(value: Double, date: Date)
    case baselineSample(value: Double?, date: Date?, referenceMedian: Double?, status: TodayBaselineAssessment.Status)
    case heartRate(HeartRateSummary)
    case failed

    var timestamp: Date? {
      switch self {
      case let .heartRate(summary): summary.latest.date
      case let .sample(_, date): date
      case let .baselineSample(_, date, _, _): date
      case .loading, .empty, .failed: nil
      }
    }
  }

  struct VerifiedRefresh: Hashable {
    let verification: UUID
    /// Earlier samples may change even when a card's latest reading stays the same.
    let loadID: UUID
  }

  @MainActor
  @Observable
  fileprivate final class Measurement {
    var state = MeasurementState.loading
    var verifiedRefresh: VerifiedRefresh?
  }

  private(set) var phase = Phase.loading
  private(set) var sleepState = SleepState.loading
  private(set) var isLoading = true
  private(set) var loadID = UUID()
  private(set) var canObserveHealthChanges = false
  private(set) var healthChangeID: UUID?
  /// Each card tracks its own reading independently.
  private let measurements = Dictionary(uniqueKeysWithValues: TodayHealthMetric.allCases.map { ($0, Measurement()) })

  @ObservationIgnored private var activeLoadToken: UUID?
  @ObservationIgnored private var pendingAuthorization: AppleHealthReadScope?
  @ObservationIgnored private var pendingHealthRefresh = false
  @ObservationIgnored private var reusingLatestHistory = false

  private let refreshTodayHealth: RefreshTodayHealth

  init(refreshTodayHealth: RefreshTodayHealth) {
    self.refreshTodayHealth = refreshTodayHealth
  }

  func measurement(for metric: TodayHealthMetric) -> MeasurementState {
    measurements[metric]?.state ?? .loading
  }

  func verifiedRefresh(for metric: TodayHealthMetric) -> VerifiedRefresh? {
    measurements[metric]?.verifiedRefresh
  }

  func readTimeline(
    for metric: TodayHealthMetric,
    in interval: DateInterval,
    refresh: VerifiedRefresh
  ) async throws -> [IntradayHealthPoint] {
    let points = try await refreshTodayHealth.readTimeline(
      for: metric,
      in: interval,
      verification: refresh.verification
    )
    try Task.checkCancellation()
    guard verifiedRefresh(for: metric) == refresh else { throw CancellationError() }
    return points
  }

  func connect() {
    guard phase == .needsConnection else { return }
    pendingAuthorization = .all
    reload()
  }

  func connectSleep() {
    guard sleepState == .needsConnection, !isLoading else { return }
    pendingAuthorization = .sleep
    reload(reusingLatest: true)
  }

  func reload() {
    reload(reusingLatest: false)
  }

  private func reload(reusingLatest: Bool) {
    guard !isLoading else { return }
    reusingLatestHistory = reusingLatest
    beginLoading()
    loadID = UUID()
  }

  func discardPendingAuthorization() {
    pendingAuthorization = nil
  }

  func revalidateReadings() {
    clearReadings()
    reusingLatestHistory = false
    beginLoading()
    loadID = UUID()
  }

  func hideReadings() {
    // Invalidate in-flight reads before SwiftUI cancels the scene's task.
    activeLoadToken = nil
    isLoading = false
    clearReadings()
  }

  private func clearReadings() {
    discardPendingHealthRefresh()
    sleepState = .loading
    for measurement in measurements.values {
      measurement.verifiedRefresh = nil
      measurement.state = .loading
    }
  }

  func receiveHealthChange() {
    guard canObserveHealthChanges, !Task.isCancelled else { return }
    healthChangeID = UUID()
  }

  func refreshAfterHealthChange(id: UUID, debounce: Duration = .milliseconds(500)) async {
    do {
      try await Task.sleep(for: debounce)
    } catch {
      return
    }
    guard id == healthChangeID, canObserveHealthChanges, !Task.isCancelled else { return }
    healthChangeID = nil
    if activeLoadToken != nil {
      pendingHealthRefresh = true
    } else {
      reload(reusingLatest: true)
    }
  }

  func discardPendingHealthRefresh() {
    healthChangeID = nil
    pendingHealthRefresh = false
  }

  func load(id: UUID) async {
    guard id == loadID, !Task.isCancelled else { return }
    let token = UUID()
    activeLoadToken = token
    pendingHealthRefresh = false
    defer { finishLoad(id: id, token: token) }

    let authorization = pendingAuthorization
    let shouldReuseHistory = reusingLatestHistory
    discardPendingAuthorization()
    reusingLatestHistory = false
    beginLoading()

    await refreshTodayHealth(
      requesting: authorization,
      reusingLatest: shouldReuseHistory,
      isCurrent: { id == loadID && token == activeLoadToken },
      onUpdate: apply
    )
  }

  private func beginLoading() {
    isLoading = true
    if phase != .ready {
      phase = .loading
    }
  }

  private func finishLoad(id: UUID, token: UUID) {
    guard token == activeLoadToken else { return }
    activeLoadToken = nil
    isLoading = false
    guard pendingHealthRefresh else { return }
    pendingHealthRefresh = false
    if id == loadID, healthChangeID == nil, canObserveHealthChanges, !Task.isCancelled {
      reload(reusingLatest: true)
    }
  }

  private func apply(_ update: RefreshTodayHealth.Update) {
    switch update {
    case .needsAuthorization:
      showStatus(.needsConnection)
    case .unavailable:
      showStatus(.unavailable)
    case .restricted:
      showStatus(.restricted)
    case .failed:
      showStatus(.failed)
    case .readingMeasurements:
      canObserveHealthChanges = true
      phase = .ready
    case .sleepNeedsAuthorization:
      sleepState = .needsConnection
    case let .sleep(summary):
      let state = summary.map(SleepState.summary) ?? .empty
      if sleepState != state {
        sleepState = state
      }
    case .sleepFailed:
      sleepState = .failed
    case let .measurement(metric, reading, verification):
      apply(reading, for: metric, verification: verification)
    }
  }

  private func apply(_ reading: RefreshTodayHealth.Reading, for metric: TodayHealthMetric, verification: UUID) {
    guard let measurement = measurements[metric] else { return }
    let state = measurementState(for: reading)
    if measurement.state != state {
      measurement.state = state
    }
    measurement.verifiedRefresh = state == .failed ? nil :
      VerifiedRefresh(verification: verification, loadID: loadID)
  }

  private func showStatus(_ phase: Phase) {
    self.phase = phase
    canObserveHealthChanges = false
    clearReadings()
  }

  private func measurementState(for reading: RefreshTodayHealth.Reading) -> MeasurementState {
    switch reading {
    case .empty: .empty
    case .failed: .failed
    case let .heartRate(summary): .heartRate(summary)
    case let .bloodOxygen(sample): .sample(value: sample.saturation, date: sample.date)
    case let .respiratoryRate(sample): .sample(value: sample.breathsPerMinute, date: sample.date)
    case let .restingHeartRate(sample, assessment):
      .baselineSample(
        value: sample?.beatsPerMinute,
        date: sample?.date,
        referenceMedian: nil,
        status: assessment.status
      )
    case let .heartRateVariability(sample, assessment):
      .baselineSample(
        value: sample?.sdnnMilliseconds,
        date: sample?.date,
        referenceMedian: assessment.todayValue,
        status: assessment.status
      )
    }
  }
}
