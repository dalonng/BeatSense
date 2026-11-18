import AARFoundation
import Foundation
import UIKit

@MainActor
public final class AppBootstrapper {
  public static let shared = AppBootstrapper()

  private init() {}

  public func configureCoreServices() {
    guard !isRunningForTestsOrPreviews else { return }

    #if DEBUG
      AppLogging.bootstrap(.init(logLevel: .debug, enableOSLog: true, enableConsole: true))
    #else
      AppLogging.bootstrap(.init(logLevel: .info, enableOSLog: true, enableConsole: false))
    #endif
  }

  public func configureUIKitDependentSDKs(launchOptions _: [UIApplication.LaunchOptionsKey: Any]?) {
    guard !isRunningForTestsOrPreviews else { return }

    // Register SDKs here when they require UIKit's launch callback or launch options.
  }

  private var isRunningForTestsOrPreviews: Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
      || environment["XCTestConfigurationFilePath"] != nil
  }
}
