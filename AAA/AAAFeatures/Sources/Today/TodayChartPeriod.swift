import Foundation

enum TodayChartPeriod: String, CaseIterable {
  case hour = "1H"
  case twelveHours = "12H"
  case day = "D"

  var hours: Int? {
    switch self {
    case .hour: 1
    case .twelveHours: 12
    case .day: nil
    }
  }

  func interval(in day: DateInterval, anchoredAt date: Date, calendar: Calendar) -> DateInterval {
    guard let hours, let hour = calendar.dateInterval(of: .hour, for: date) else { return day }
    let duration = min(day.duration, TimeInterval(hours * 3600))
    // At the start of the day, extend forward to keep the entire selected span on today's axis.
    let end = min(day.end, max(day.start.addingTimeInterval(duration), hour.end))
    return DateInterval(start: end.addingTimeInterval(-duration), end: end)
  }
}
