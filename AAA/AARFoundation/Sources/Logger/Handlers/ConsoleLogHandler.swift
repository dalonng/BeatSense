import Foundation
import Logging

/// Writes SwiftLog events to stdout. Supply only messages and metadata safe to display in cleartext.
public struct ConsoleLogHandler: LogHandler {
  public let label: String
  public var logLevel: Logging.Logger.Level
  public var metadata: Logging.Logger.Metadata = [:]
  public var metadataProvider: Logging.Logger.MetadataProvider?

  private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

  public init(
    label: String,
    logLevel: Logging.Logger.Level = .trace,
    metadataProvider: Logging.Logger.MetadataProvider? = nil
  ) {
    self.label = label
    self.logLevel = logLevel
    self.metadataProvider = metadataProvider
  }

  public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  public func log(event: LogEvent) {
    let badge = switch event.level {
    case .trace: "🟣 TRACE"
    case .debug: "🔵 DEBUG"
    case .info: "🟢 INFO"
    case .notice: "🩵 NOTICE"
    case .warning: "🟡 WARN"
    case .error: "🔴 ERROR"
    case .critical: "💥 CRITICAL"
    }
    let timestamp = Date.now.formatted(Self.timestampStyle)
    let fileName = LogFormatting.fileName(from: event.file)
    let payload = LogFormatting.formatPayload(event, base: metadata, provider: metadataProvider)
    print("\(timestamp) \(badge) [\(label)] [\(fileName):\(event.line)] \(payload)")
  }
}
