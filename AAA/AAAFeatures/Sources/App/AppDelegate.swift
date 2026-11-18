import UIKit

@MainActor
public final class AppDelegate: NSObject, UIApplicationDelegate {
  public func application(
    _: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    AppBootstrapper.shared.configureUIKitDependentSDKs(launchOptions: launchOptions)
    return true
  }
}
