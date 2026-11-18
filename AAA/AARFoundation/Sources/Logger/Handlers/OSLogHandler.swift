import Logging
import os

/// Sends SwiftLog events to Unified Logging with private messages and metadata.
public struct OSLogHandler: LogHandler {
  public var logLevel: Logging.Logger.Level
  public var metadata: Logging.Logger.Metadata = [:]
  public var metadataProvider: Logging.Logger.MetadataProvider?

  private let destination: OSLog

  public init(
    subsystem: String,
    category: String,
    logLevel: Logging.Logger.Level = .debug,
    metadataProvider: Logging.Logger.MetadataProvider? = nil
  ) {
    destination = OSLog(subsystem: subsystem, category: category)
    self.logLevel = logLevel
    self.metadataProvider = metadataProvider
  }

  public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  public func log(event: LogEvent) {
    let level: OSLogType = switch event.level {
    case .trace, .debug: .debug
    case .info: .info
    case .notice, .warning: .default
    case .error: .error
    case .critical: .fault
    }
    guard destination.isEnabled(type: level) else { return }

    let fileName = String(LogFormatting.fileName(from: event.file))
    let payload = LogFormatting.formatPayload(event, base: metadata, provider: metadataProvider)
    os.Logger(destination).log(
      level: level,
      "[\(fileName, privacy: .public):\(event.line, privacy: .public)] \(payload, privacy: .private)"
    )
  }
}
