import Foundation
import Logging
import Synchronization

public enum AppLogging {
  public struct Configuration: Sendable {
    public let subsystem: String
    public let logLevel: Logger.Level
    public let enableOSLog: Bool
    public let enableConsole: Bool
    public let metadataProvider: Logger.MetadataProvider?

    public init(
      subsystem: String = Bundle.main.bundleIdentifier ?? "BeatSense",
      logLevel: Logger.Level = .debug,
      enableOSLog: Bool = true,
      enableConsole: Bool = false,
      metadataProvider: Logger.MetadataProvider? = nil
    ) {
      self.subsystem = subsystem
      self.logLevel = logLevel
      self.enableOSLog = enableOSLog
      self.enableConsole = enableConsole
      self.metadataProvider = metadataProvider
    }
  }

  private static let defaultSubsystem = Configuration().subsystem
  private static let installedSubsystem = Mutex<String?>(nil)

  public static var subsystem: String {
    installedSubsystem.withLock { $0 } ?? defaultSubsystem
  }

  /// Installs the process-wide SwiftLog backend. The first configuration wins.
  /// Call this before creating SwiftLog loggers and make this the sole owner of bootstrap.
  public static func bootstrap(_ config: Configuration = .init()) {
    installedSubsystem.withLock { subsystem in
      guard subsystem == nil else { return }

      LoggingSystem.bootstrap(
        { label, provider in
          var handlers: [any LogHandler] = []
          if config.enableOSLog {
            handlers.append(OSLogHandler(
              subsystem: config.subsystem,
              category: label,
              logLevel: config.logLevel,
              metadataProvider: provider
            ))
          }
          if config.enableConsole {
            handlers.append(ConsoleLogHandler(label: label, logLevel: config.logLevel, metadataProvider: provider))
          }

          switch handlers.count {
          case 0: return SwiftLogNoOpLogHandler()
          case 1: return handlers[0]
          default: return MultiplexLogHandler(handlers)
          }
        },
        metadataProvider: config.metadataProvider
      )
      subsystem = config.subsystem
    }
  }

  public static func logger(category: String) -> Logger {
    Logger(label: category)
  }
}
