import AACUseCases
import Foundation
import Observation

@MainActor
@Observable
final class TrendsViewModel {
  enum Phase {
    case loading
    case needsConnection
    case unavailable
    case restricted
    case ready(RefreshHealthTrends.Snapshot)
    case failed
  }

  private(set) var phase = Phase.loading
  // A completed load stays settled across tab switches. A cancelled load remains pending for the next appearance.
  private(set) var loadID: UUID? = UUID()
  var isLoading: Bool {
    loadID != nil
  }

  @ObservationIgnored private var activeLoadToken: UUID?
  @ObservationIgnored private var isConnecting = false
  @ObservationIgnored private var authorizationRequested = false
  @ObservationIgnored private var reuseVerifiedHistory = false

  private let refreshHealthTrends: RefreshHealthTrends

  init(refreshHealthTrends: RefreshHealthTrends) {
    self.refreshHealthTrends = refreshHealthTrends
  }

  func connect() {
    guard case .needsConnection = phase, !isConnecting else { return }
    isConnecting = true
    authorizationRequested = true
    scheduleLoad(hidingReadings: true)
  }

  func reload() {
    guard !isConnecting else { return }
    if case .ready = phase {
      scheduleLoad(hidingReadings: false)
    } else {
      scheduleLoad(hidingReadings: true)
    }
  }

  func revalidate() {
    guard !isConnecting else { return }
    scheduleLoad(hidingReadings: true)
  }

  func receiveHealthChange() {
    guard !isConnecting else { return }
    scheduleLoad(hidingReadings: false, reusingLatest: true)
  }

  func hideReadings() {
    isConnecting = false
    authorizationRequested = false
    scheduleLoad(hidingReadings: true)
  }

  func cancelConnection() {
    if isConnecting {
      hideReadings()
    }
  }

  func load(id: UUID, retentionDays: Int) async {
    guard id == loadID, !Task.isCancelled else { return }
    let token = UUID()
    let requestAuthorization = authorizationRequested
    let reusingLatest = reuseVerifiedHistory
    activeLoadToken = token
    authorizationRequested = false
    reuseVerifiedHistory = false
    defer {
      if activeLoadToken == token {
        activeLoadToken = nil
        isConnecting = false
      }
    }

    let nextPhase: Phase
    do {
      let snapshot = try await refreshHealthTrends(
        requestAuthorization: requestAuthorization,
        reusingLatest: reusingLatest,
        retentionDays: retentionDays
      )
      nextPhase = .ready(snapshot)
    } catch RefreshHealthTrends.LoadError.needsAuthorization {
      nextPhase = .needsConnection
    } catch RefreshHealthTrends.LoadError.unavailable {
      nextPhase = .unavailable
    } catch RefreshHealthTrends.LoadError.restricted {
      nextPhase = .restricted
    } catch {
      nextPhase = .failed
    }
    guard id == loadID, activeLoadToken == token, !Task.isCancelled else { return }
    phase = nextPhase
    loadID = nil
  }

  private func scheduleLoad(hidingReadings: Bool, reusingLatest: Bool = false) {
    activeLoadToken = nil
    reuseVerifiedHistory = reusingLatest
    if hidingReadings {
      phase = .loading
    }
    loadID = UUID()
  }
}
