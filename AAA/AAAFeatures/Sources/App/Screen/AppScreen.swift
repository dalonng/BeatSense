import AACUseCases
import AAMServices
import AAODesignSystem
import SwiftUI

public struct AppScreen: View {
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage(SynchronizeHealthHistory.retentionPreferenceKey) private var retentionDays = SynchronizeHealthHistory
    .defaultRetentionDays
  @State private var model: AppViewModel

  public init(appleHealth: any AppleHealthReading, synchronizeHealthHistory: SynchronizeHealthHistory) {
    _model = State(initialValue: AppViewModel(
      appleHealth: appleHealth,
      synchronizeHealthHistory: synchronizeHealthHistory
    ))
  }

  public var body: some View {
    TabView {
      Tab(.tabToday, systemImage: "heart.fill") {
        TodayScreen(
          refreshTodayHealth: model.refreshTodayHealth,
          retentionDays: $retentionDays,
          healthChangeID: model.healthChangeID,
          healthAuthorizationChangeID: model.healthAuthorizationChangeID,
          today: model.today
        )
      }

      Tab(.tabTrends, systemImage: "chart.bar.fill") {
        TrendsScreen(model: model.trends, retentionDays: retentionDays)
      }

      Tab(.tabLongevity, systemImage: "hourglass") {
        Color.clear
      }

      Tab(.tabHealthInsights, systemImage: "text.book.closed.fill") {
        Color.clear
      }
    }
    .background(AppColors.background.ignoresSafeArea())
    .tint(AppColors.tint)
    .task(id: scenePhase == .active) {
      guard scenePhase == .active else { return }
      await model.observeForeground()
    }
    .task(id: retentionDays) {
      await model.setRetentionDays(retentionDays)
    }
    .onChange(of: retentionDays) {
      model.trends.revalidate()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background {
        model.trends.hideReadings()
      } else if phase == .active {
        model.trends.revalidate()
      }
    }
  }
}
