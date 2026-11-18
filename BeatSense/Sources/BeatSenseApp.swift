import AAAFeatures
import AACUseCases
import AAMServices
import AAMStorages
import Foundation
import SwiftUI

@main
struct BeatSenseApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  private let appleHealth: AppleHealthClient
  private let synchronizeHealthHistory: SynchronizeHealthHistory

  init() {
    AppBootstrapper.shared.configureCoreServices()

    let appleHealth = AppleHealthClient()
    self.appleHealth = appleHealth
    synchronizeHealthHistory = SynchronizeHealthHistory(
      appleHealth: appleHealth,
      store: HealthHistoryStore(),
      retentionDays: UserDefaults.standard.object(forKey: SynchronizeHealthHistory.retentionPreferenceKey) as? Int
        ?? SynchronizeHealthHistory.defaultRetentionDays
    )
  }

  var body: some Scene {
    WindowGroup {
      AppScreen(appleHealth: appleHealth, synchronizeHealthHistory: synchronizeHealthHistory)
    }
  }
}
