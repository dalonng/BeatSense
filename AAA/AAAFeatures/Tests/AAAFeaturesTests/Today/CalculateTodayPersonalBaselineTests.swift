@testable import AACUseCases
import AANModels
import Foundation
import Testing

struct CalculateTodayPersonalBaselineTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }

  private var midnight: Date {
    Date(timeIntervalSince1970: 1_767_225_600)
  }

  @Test(arguments: [20, 21])
  func `counts valid completed days within the rolling window`(validDays: Int) throws {
    let calculator = try calculator()
    var samples = ((29 - validDays) ... 28).flatMap { day in
      [restingHeartRate(95, day: -day, hour: 7), restingHeartRate(60, day: -day, hour: 10)]
    }
    samples += [
      restingHeartRate(60, day: -29),
      restingHeartRate(90, hour: 7),
      restingHeartRate(65, hour: 10),
    ]

    let reading = calculator.restingHeartRate(samples)
    #expect(reading.assessment.todayValue == 65)
    #expect(reading.baseline.validDayCount == validDays)
    let expectedMedian: Double? = validDays == 20 ? nil : 60
    #expect(reading.baseline.p50 == expectedMedian)
    let expected: TodayBaselineAssessment.Status = validDays == 20 ? .building :
      .compared(difference: 5, position: .aboveRange)
    #expect(reading.assessment.status == expected)
  }

  @Test(arguments: zip(
    [51.0, 52.0, 68.0, 69.0],
    [
      TodayBaselineAssessment.Position.belowRange,
      .withinRange,
      .withinRange,
      .aboveRange,
    ]
  ))
  func `compares against the median and inclusive 10th and 90th percentiles`(
    value: Double,
    position: TodayBaselineAssessment.Position
  ) throws {
    let calculator = try calculator()
    let history = (1 ... 21).map { restingHeartRate(Double(49 + $0), day: -$0) }
    let reading = calculator.restingHeartRate(history + [restingHeartRate(value)])

    #expect(reading.baseline.p10 == 52)
    #expect(reading.baseline.p50 == 60)
    #expect(reading.baseline.p90 == 68)
    #expect(reading.assessment.status == .compared(difference: value - 60, position: position))
  }

  @Test func `HRV uses comparable samples for both the current and historical daily medians`() throws {
    let calculator = try calculator()
    var samples = (1 ... 21).flatMap { day in
      [
        hrv(40, day: -day, hour: 10),
        hrv(60, day: -day, hour: 11),
        hrv(120, day: -day, hour: 10, source: "other app"),
        hrv(120, day: -day, hour: 10, device: "other watch"),
        hrv(120, day: -day, hour: 10, duration: 30),
        hrv(.nan, day: -day, hour: 10),
      ]
    }
    samples += (1 ... 20).map { hrv(120, day: -$0, hour: 9) }
    samples += [hrv(99, hour: 9), hrv(38, hour: 10), hrv(58, hour: 11), hrv(99, hour: 12)]

    let reading = calculator.heartRateVariability(samples)
    #expect(reading.latest?.sdnnMilliseconds == 58)
    #expect(reading.assessment.todayValue == 48)
    #expect(reading.assessment.status == .compared(difference: -2, position: .belowRange))
  }

  @Test(arguments: [false, true])
  func `HRV counts covered days and compares only today's selected period`(hasNightReading: Bool) throws {
    let calculator = try calculator()
    let nights = (1 ... 26).map { hrv(40, day: -$0, hour: 3) }
    let mornings = (1 ... 2).flatMap { day in
      (1 ... 20).map { hrv(Double($0), day: -day, hour: 10) }
    }
    let latest = hrv(80, hour: 11)
    let current = hasNightReading ? [hrv(54, hour: 3), latest] : [latest]

    let reading = calculator.heartRateVariability(nights + mornings + current)

    #expect(reading.baseline.referencePeriod == 1)
    #expect(reading.baseline.validDayCount == 26)
    #expect(reading.baseline.p50 == 40)
    #expect(reading.latest == latest.sample)
    #expect(reading.assessment.todayValue == (hasNightReading ? 54 : nil))
    let expected: TodayBaselineAssessment.Status = hasNightReading ?
      .compared(difference: 14, position: .aboveRange) : .noCurrentReading
    #expect(reading.assessment.status == expected)
  }

  @Test func `equally covered HRV periods select the same earlier period regardless of input order`() throws {
    let calculator = try calculator()
    let history = (1 ... 21).flatMap { day in
      [hrv(45, day: -day, hour: 1), hrv(60, day: -day, hour: 3)]
    }
    let samples = history + [hrv(62, hour: 3)]

    for ordered in [samples, Array(samples.reversed())] {
      let reading = calculator.heartRateVariability(ordered)
      #expect(reading.baseline.referencePeriod == 0)
      #expect(reading.baseline.validDayCount == 21)
      #expect(reading.baseline.p50 == 45)
      #expect(reading.assessment.status == .noCurrentReading)
    }
  }

  @Test func `an older reading is kept without a daily comparison`() throws {
    let calculator = try calculator()
    let history = (1 ... 21).map { restingHeartRate(60, day: -$0) }

    let reading = calculator.restingHeartRate(history)

    #expect(reading.latest == history.first?.sample)
    #expect(reading.assessment.todayValue == nil)
    #expect(reading.assessment.status == .noCurrentReading)
    #expect(reading.baseline.p10 == 60)
    #expect(reading.baseline.p50 == 60)
    #expect(reading.baseline.p90 == 60)
    #expect(reading.baseline.windowStart == calculator.queryInterval.start)
    #expect(reading.baseline.windowEnd == midnight)
  }

  @Test func `stored HRV baseline is reusable for the same comparison context`() throws {
    let calculator = try calculator()
    let history = (1 ... 21).map { hrv(50, day: -$0, hour: 10) }
    let samples = history + [hrv(60, hour: 10)]
    let baseline = calculator.heartRateVariability(samples).baseline

    let sameContext = calculator.heartRateVariability(samples, reusing: baseline)
    #expect(sameContext.baseline == baseline)
    #expect(sameContext.assessment.status == .compared(difference: 10, position: .aboveRange))

    let differentContext = calculator.heartRateVariability(
      samples + [hrv(60, hour: 11, device: "other watch")],
      reusing: baseline
    )
    #expect(differentContext.baseline.deviceIdentifier == "other watch")
    #expect(differentContext.baseline.validDayCount == 0)
    #expect(differentContext.baseline.p50 == nil)
    #expect(differentContext.assessment.status == .building)
  }

  @Test func `a new day keeps the qualified period and recording duration while updating its quantiles`() throws {
    let history = (1 ... 21).map { hrv(Double($0), day: -$0, hour: 3) }
    let stored = try calculator().heartRateVariability(history).baseline
    let interval = DateInterval(start: date(day: -6, hour: 12), end: date(day: 1, hour: 12))
    let next = try #require(CalculateTodayPersonalBaseline(recentInterval: interval, calendar: calendar))
    let latest = hrv(80, day: 1, hour: 10, duration: 180)
    let reading = next.heartRateVariability(history + [hrv(30, hour: 3), latest], reusing: stored)

    #expect(reading.baseline.referencePeriod == stored.referencePeriod)
    #expect(reading.baseline.referenceDuration == 60)
    #expect(reading.baseline.validDayCount == 22)
    #expect(reading.baseline.p50 == 11.5)
    #expect(reading.latest == latest.sample)
    #expect(reading.assessment.status == .noCurrentReading)
  }

  @Test(arguments: [1, 2])
  func `reselects the HRV period and recalculates quantiles on algorithm upgrade`(version: Int) throws {
    let calculator = try calculator()
    let cachedBaseline = PersonalBaseline(
      p10: 50,
      p50: 50,
      p90: 50,
      validDayCount: 21,
      windowStart: calculator.queryInterval.start,
      windowEnd: midnight,
      timeZoneID: calendar.timeZone.identifier,
      sourceIdentifier: "watch",
      deviceIdentifier: "device",
      referencePeriod: 0,
      referenceDuration: 60,
      algorithmVersion: version,
      computedAt: midnight
    )
    let early = (1 ... 21).map { hrv(50, day: -$0, hour: 1) }
    let later = (1 ... 26).map { hrv(60, day: -$0, hour: 3) }
    let reading = calculator.heartRateVariability(early + later + [hrv(55, hour: 1)], reusing: cachedBaseline)

    #expect(reading.baseline.referencePeriod == 1)
    #expect(reading.baseline.algorithmVersion == 3)
    #expect(reading.baseline.validDayCount == 26)
    #expect(reading.baseline.p50 == 60)
    #expect(reading.assessment.status == .noCurrentReading)
  }

  @Test func `window boundaries fall on local midnights across daylight saving time`() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12)))
    let interval = DateInterval(start: now.addingTimeInterval(-7 * 86400), end: now)
    let calculator = try #require(CalculateTodayPersonalBaseline(recentInterval: interval, calendar: calendar))

    #expect(calendar.dateComponents([.day], from: calculator.queryInterval.start, to: calendar.startOfDay(for: now))
      .day == 28)
    #expect(calendar.component(.hour, from: calculator.queryInterval.start) == 0)
    #expect(calendar.component(.minute, from: calculator.queryInterval.start) == 0)
    #expect(calculator.queryInterval.end == now)
  }

  private func calculator() throws -> CalculateTodayPersonalBaseline {
    let interval = DateInterval(start: midnight.addingTimeInterval(-7 * 86400), end: date(day: 0, hour: 12))
    return try #require(CalculateTodayPersonalBaseline(recentInterval: interval, calendar: calendar))
  }

  private func date(day: Int, hour: Int) -> Date {
    midnight.addingTimeInterval(Double(day * 86400 + hour * 3600))
  }

  private func restingHeartRate(
    _ value: Double,
    day: Int = 0,
    hour: Int = 8
  ) -> SourcedHealthSample<RestingHeartRateSample> {
    .init(
      sample: .init(beatsPerMinute: value, date: date(day: day, hour: hour)),
      sourceIdentifier: "watch",
      deviceIdentifier: "device",
      duration: 0
    )
  }

  private func hrv(
    _ value: Double,
    day: Int = 0,
    hour: Int,
    source: String = "watch",
    device: String = "device",
    duration: TimeInterval = 60
  ) -> SourcedHealthSample<HeartRateVariabilitySample> {
    .init(
      sample: .init(sdnnMilliseconds: value, date: date(day: day, hour: hour)),
      sourceIdentifier: source,
      deviceIdentifier: device,
      duration: duration
    )
  }
}
