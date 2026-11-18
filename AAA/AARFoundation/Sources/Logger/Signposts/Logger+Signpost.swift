import Logging
import OSLog

public extension Logging.Logger {
  var signposter: OSSignposter {
    OSSignposter(subsystem: AppLogging.subsystem, category: label)
  }

  func emitSignpostEvent(_ name: StaticString, message: String = "") {
    let signposter = signposter
    if signposter.isEnabled {
      signposter.emitEvent(name, id: signposter.makeSignpostID(), "\(message, privacy: .private)")
    }
    trace("📍 Signpost Event [\(name)]")
  }

  func withSignpost<T, E: Error>(
    _ name: StaticString,
    message: String = "",
    operation: () throws(E) -> T
  ) throws(E) -> T {
    let signposter = signposter
    let state = beginSignpost(name, message: message, using: signposter)
    defer { endSignpost(name, state: state, using: signposter) }
    return try operation()
  }

  nonisolated(nonsending) func withAsyncSignpost<T, E: Error>(
    _ name: StaticString,
    message: String = "",
    operation: nonisolated(nonsending) () async throws(E) -> T
  ) async throws(E) -> T {
    let signposter = signposter
    let state = beginSignpost(name, message: message, using: signposter)
    defer { endSignpost(name, state: state, using: signposter) }
    return try await operation()
  }

  private func beginSignpost(
    _ name: StaticString,
    message: String,
    using signposter: OSSignposter
  ) -> OSSignpostIntervalState? {
    trace("▶️ Signpost Begin [\(name)]")
    guard signposter.isEnabled else { return nil }
    return signposter.beginInterval(name, id: signposter.makeSignpostID(), "\(message, privacy: .private)")
  }

  private func endSignpost(_ name: StaticString, state: OSSignpostIntervalState?, using signposter: OSSignposter) {
    if let state {
      signposter.endInterval(name, state)
    }
    trace("⏹️ Signpost End [\(name)]")
  }
}
