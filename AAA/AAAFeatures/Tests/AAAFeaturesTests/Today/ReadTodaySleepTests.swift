@testable import AACUseCases
import AANModels
import Foundation
import Testing

struct ReadTodaySleepTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }

  private let midnight = Date(timeIntervalSince1970: 1_767_225_600)

  @Test func `counts duplicate sleep once and subtracts explicit wake from overlapping sleep sources`() async throws {
    let samples = [
      sample(64, 489), sample(64, 180), sample(100, 180), sample(180, 400), sample(400, 489),
      sample(150, 160, .awake), sample(159, 161, .awake), sample(760, 800),
    ]
    for order in [samples, Array(samples.reversed())] {
      let result = try #require(await read(order))
      #expect(result == TodaySleepSummary(
        startDate: date(64),
        endDate: date(489),
        stageDurations: [.asleep: 414 * 60, .awake: 11 * 60]
      ))
    }
  }

  @Test func `selects longest sleep ending today across midnight and keeps short gaps out of its duration`(
  ) async throws {
    let result = try await read([
      sample(-1400, -800), sample(-30, 100), sample(190, 400), sample(750, 810),
    ])
    #expect(result == TodaySleepSummary(startDate: date(-30), endDate: date(400), stageDurations: [.asleep: 340 * 60]))
  }

  @Test func `separates sessions after a longer gap and uses the latest end for equal durations`() async throws {
    let result = try await read([sample(30, 90), sample(181, 241)])
    #expect(result == TodaySleepSummary(startDate: date(181), endDate: date(241), stageDurations: [.asleep: 60 * 60]))
  }

  @Test func `attributes each instant once when specific stages overlap or conflict`() async throws {
    let samples = [
      sample(0, 100), sample(10, 40, .core), sample(10, 40, .core),
      sample(35, 80, .deep), sample(70, 100, .rem), sample(50, 55, .awake),
    ]
    let expected: [SleepSample.State: TimeInterval] = [
      .core: 25 * 60, .deep: 25 * 60, .rem: 20 * 60, .asleep: 25 * 60, .awake: 5 * 60,
    ]
    for order in [samples, Array(samples.reversed())] {
      let result = try #require(await read(order))
      #expect(result.stageDurations == expected)
      #expect(result.asleepDuration == 95 * 60)
    }
  }

  @Test func `reports only observed awakenings inside the selected session`() async throws {
    let result = try #require(await read([
      sample(25, 35, .awake), sample(30, 60, .deep), sample(55, 80, .awake),
      sample(90, 120, .rem), sample(115, 290, .awake), sample(300, 320, .core),
    ]))
    #expect(result.startDate == date(35))
    #expect(result.endDate == date(115))
    let expected: [SleepSample.State: TimeInterval] = [.deep: 20 * 60, .rem: 25 * 60, .awake: 25 * 60]
    #expect(result.stageDurations == expected)
    #expect(result.asleepDuration == 45 * 60)
  }

  @Test func `ignores prior waking days future records and intervals without measured sleep`() async throws {
    #expect(try await read([sample(-300, -100), sample(10, 10), sample(800, 1200), sample(300, 420, .awake)]) == nil)
    #expect(try await read([sample(10, 100), sample(0, 150, .awake)]) == nil)
    #expect(try await read([sample(-180, 0)])?.endDate == midnight)
  }

  @Test func `uses local day boundaries and elapsed time through the repeated hour`() async throws {
    var calendar = calendar
    calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let start = try Date("2026-11-01T06:30:00Z", strategy: .iso8601) // Oct 31, 23:30 PDT
    let end = try Date("2026-11-01T15:30:00Z", strategy: .iso8601) // Nov 1, 07:30 PST
    let now = try Date("2026-11-01T20:00:00Z", strategy: .iso8601)
    let queryStart = try Date("2026-10-31T07:00:00Z", strategy: .iso8601)
    let reader = MockAppleHealthReader()
    await reader.setSleepSamples([SleepSample(interval: DateInterval(start: start, end: end), state: .deep)])
    let result = try await ReadTodaySleep(appleHealth: reader)(now: now, calendar: calendar)
    #expect(await reader.sleepQueries == [DateInterval(start: queryStart, end: now)])
    #expect(result == TodaySleepSummary(startDate: start, endDate: end, stageDurations: [.deep: 9 * 3600]))
  }

  private func date(_ minute: Int) -> Date {
    midnight.addingTimeInterval(TimeInterval(minute) * 60)
  }

  private func sample(_ start: Int, _ end: Int, _ state: SleepSample.State = .asleep) -> SleepSample {
    SleepSample(interval: DateInterval(start: date(start), end: date(end)), state: state)
  }

  private func read(_ samples: [SleepSample]) async throws -> TodaySleepSummary? {
    let reader = MockAppleHealthReader()
    await reader.setSleepSamples(samples)
    return try await ReadTodaySleep(appleHealth: reader)(now: date(1080), calendar: calendar)
  }
}
