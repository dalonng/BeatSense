import AAMServices

struct PrepareHealthHistoryRead: Sendable {
  enum Status {
    case ready
    case needsAuthorization
    case unavailable
    case restricted
    case failed
    case cancelled
  }

  let appleHealth: any AppleHealthReading
  let synchronizeHealthHistory: SynchronizeHealthHistory

  func callAsFunction(requesting scope: AppleHealthReadScope?) async -> Status {
    guard !Task.isCancelled else { return .cancelled }
    do {
      if let scope {
        try await appleHealth.requestReadAuthorization(for: scope)
        await synchronizeHealthHistory.invalidateAuthorization()
      } else if try await appleHealth.needsAuthorizationRequest(for: .measurements) {
        guard !Task.isCancelled else { return .cancelled }
        await synchronizeHealthHistory.invalidateAuthorization()
        return .needsAuthorization
      }
      return .ready
    } catch {
      guard !Task.isCancelled else { return .cancelled }
      await synchronizeHealthHistory.invalidateAuthorization()
      switch error {
      case is CancellationError where scope != nil: return .needsAuthorization
      case AppleHealthError.unavailable: return .unavailable
      case AppleHealthError.restricted: return .restricted
      default: return .failed
      }
    }
  }
}
