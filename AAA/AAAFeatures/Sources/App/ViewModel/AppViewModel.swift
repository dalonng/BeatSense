import AACUseCases
import AAMServices
import Foundation
import Observation

@MainActor
@Observable
final class AppViewModel {
  private(set) var healthChangeID: UUID?
  private(set) var healthAuthorizationChangeID: UUID?
  private(set) var today = Calendar.current.dateInterval(of: .day, for: .now)

  let refreshTodayHealth: RefreshTodayHealth
  let trends: TrendsViewModel
  private let synchronizeHealthHistory: SynchronizeHealthHistory

  init(appleHealth: any AppleHealthReading, synchronizeHealthHistory: SynchronizeHealthHistory) {
    self.synchronizeHealthHistory = synchronizeHealthHistory
    refreshTodayHealth = RefreshTodayHealth(
      appleHealth: appleHealth,
      synchronizeHealthHistory: synchronizeHealthHistory
    )
    trends = TrendsViewModel(refreshHealthTrends: RefreshHealthTrends(
      appleHealth: appleHealth,
      synchronizeHealthHistory: synchronizeHealthHistory
    ))
  }

  func observeForeground() async {
    await synchronizeHealthHistory.observeForeground { changes in
      await withDiscardingTaskGroup { group in
        group.addTask { await self.observeCalendarChanges() }
        for await change in changes {
          guard !Task.isCancelled else { break }
          switch change {
          case .authorizationInvalidated:
            self.healthAuthorizationChangeID = UUID()
            self.trends.revalidate()
          case .updated:
            self.trends.receiveHealthChange()
          }
          self.healthChangeID = UUID()
        }
        group.cancelAll()
      }
    }
  }

  func setRetentionDays(_ days: Int) async {
    await synchronizeHealthHistory.setRetentionDays(days)
  }

  private func observeCalendarChanges() async {
    let center = NotificationCenter.default
    let (changes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let day = center.addObserver(of: Calendar.self, for: .calendarDayChanged) { _ in
      continuation.yield()
    }
    let timeZone = center.addObserver(of: TimeZone.self, for: .systemTimeZoneDidChange) { _ in
      continuation.yield()
    }
    let clock = center.addObserver(of: Date.self, for: .systemClockDidChange) { _ in
      continuation.yield()
    }
    defer {
      center.removeObserver(day)
      center.removeObserver(timeZone)
      center.removeObserver(clock)
      continuation.finish()
    }

    // Catch calendar changes that occurred while the scene was inactive.
    continuation.yield()
    for await _ in changes {
      guard !Task.isCancelled else { return }
      let today = Calendar.current.dateInterval(of: .day, for: .now)
      if self.today != today {
        self.today = today
        trends.revalidate()
      }
      await synchronizeHealthHistory.calendarDidChange()
    }
  }
}
