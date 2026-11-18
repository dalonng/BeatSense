@testable import AAAFeatures
import Foundation
import Testing

struct TodayChartPeriodTests {
  @Test func `hour windows end at the hour containing the reading and stay within today`() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Kathmandu"))
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 20, minute: 14)))
    let day = try #require(calendar.dateInterval(of: .day, for: date))
    #expect(TodayChartPeriod.allCases.map(\.rawValue) == ["1 H", "12H", "D"])
    let expected = [(TodayChartPeriod.hour, 20, 21), (.twelveHours, 9, 21)]
    for (period, start, end) in expected {
      #expect(period.interval(in: day, anchoredAt: date, calendar: calendar) == DateInterval(
        start: day.start.addingTimeInterval(Double(start) * 3600),
        end: day.start.addingTimeInterval(Double(end) * 3600)
      ))
    }
    #expect(TodayChartPeriod.day.interval(in: day, anchoredAt: date, calendar: calendar) == day)
    #expect(TodayChartPeriod.twelveHours.interval(in: day, anchoredAt: day.start, calendar: calendar) ==
      DateInterval(start: day.start, duration: 12 * 3600))
  }

  @Test func `repeated clock hours select distinct hourly readings on a 25 hour day`() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let first = try Date("2026-11-01T05:14:00Z", strategy: .iso8601)
    let second = first.addingTimeInterval(3600)
    let day = try #require(calendar.dateInterval(of: .day, for: first))
    let earlier = TodayChartPeriod.hour.interval(in: day, anchoredAt: first, calendar: calendar)
    let later = TodayChartPeriod.hour.interval(in: day, anchoredAt: second, calendar: calendar)
    #expect(earlier.end == later.start)
    #expect((earlier.start ..< earlier.end).contains(first))
    #expect((later.start ..< later.end).contains(second))
    #expect(later.duration == 3600)
    #expect(TodayChartPeriod.day.interval(in: day, anchoredAt: second, calendar: calendar).duration == 25 * 3600)
  }
}
