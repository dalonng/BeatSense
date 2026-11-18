@testable import AACUseCases
import AAMStorages
import AANModels
import Foundation
import Testing

struct IntradayHealthTimelineTests {
  @Test func `keeps sparse readings and both occurrences of a repeated local hour`() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let first = try Date("2026-11-01T05:30:00Z", strategy: .iso8601)
    let second = try Date("2026-11-01T06:30:00Z", strategy: .iso8601)
    let day = try #require(calendar.dateInterval(of: .day, for: first))
    #expect(day.duration == 25 * 3600)
    var timeline = IntradayHealthTimeline(interval: day)
    let valid = [
      IntradayHealthPoint(date: day.start, value: 0),
      IntradayHealthPoint(date: first, value: 35),
      IntradayHealthPoint(date: first.addingTimeInterval(1), value: 42),
      IntradayHealthPoint(date: first.addingTimeInterval(2), value: 48),
      IntradayHealthPoint(date: second, value: 46),
    ]
    for point in valid.reversed() {
      timeline.add(measurement(.heartRateVariability, value: point.value, date: point.date))
    }
    timeline.add(measurement(.heartRateVariability, value: 50, date: day.start.addingTimeInterval(-1)))
    timeline.add(measurement(.heartRateVariability, value: 50, date: day.end))
    timeline.add(measurement(.heartRateVariability, value: -1, date: second))
    #expect(timeline.points == valid)
  }

  @Test func `bounds dense days to actual extrema and the latest measurement`() {
    let start = Date(timeIntervalSinceReferenceDate: 100)
    let day = DateInterval(start: start, duration: 86400)
    var timeline = IntradayHealthTimeline(interval: day)
    for index in (0 ..< 96).reversed() {
      let bucket = start.addingTimeInterval(Double(index) * 900)
      timeline.add(measurement(.heartRate, value: 70, date: bucket.addingTimeInterval(2)))
      timeline.add(measurement(.heartRate, value: 90, date: bucket.addingTimeInterval(1)))
      timeline.add(measurement(.heartRate, value: 50, date: bucket))
    }
    let points = timeline.points
    #expect(points.count == 193)
    #expect(points.map(\.date) == points.map(\.date).sorted())
    #expect(points.filter { $0.value == 50 }.count == 96)
    #expect(points.filter { $0.value == 90 }.count == 96)
    #expect(points.last == IntradayHealthPoint(date: start.addingTimeInterval(95 * 900 + 2), value: 70))
  }

  @MainActor
  @Test func `reads only the requested verified metric and day without another HealthKit sync`() async throws {
    let calendar = Calendar.current
    let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: .now))
    let day = try #require(calendar.dateInterval(of: .day, for: yesterday))
    let samples = TodayHealthMetric.allCases.flatMap { metric in
      [day.start.addingTimeInterval(-1), day.start, day.end.addingTimeInterval(-1), day.end].map {
        measurement(metric, value: metric == .bloodOxygen ? 0.98 : 56, date: $0)
      }
    }
    let reader = MockAppleHealthReader(samples: samples)
    let store = HealthHistoryStore(inMemory: true)
    let sync = SynchronizeHealthHistory(appleHealth: reader, store: store)
    let refresh = RefreshTodayHealth(appleHealth: reader, synchronizeHealthHistory: sync)
    var verifications: [TodayHealthMetric: UUID] = [:]
    await refresh(isCurrent: { true }, onUpdate: { update in
      if case let .measurement(metric, _, verification) = update {
        verifications[metric] = verification
      }
    })
    let queries = await reader.queryStarts.count
    for metric in TodayHealthMetric.allCases {
      let verification = try #require(verifications[metric])
      let value = metric == .bloodOxygen ? 0.98 : 56.0
      #expect(try await refresh.readTimeline(for: metric, in: day, verification: verification) == [
        IntradayHealthPoint(date: day.start, value: value),
        IntradayHealthPoint(date: day.end.addingTimeInterval(-1), value: value),
      ])
    }
    #expect(await reader.queryStarts.count == queries)

    let previous = try #require(verifications[.heartRate])
    await sync.invalidate()
    // The store contains readable data again, but a card from before invalidation cannot read it.
    await refresh(isCurrent: { true }, onUpdate: { _ in })
    await #expect(throws: HealthHistoryStore.StoreError.unverified) {
      try await refresh.readTimeline(for: .heartRate, in: day, verification: previous)
    }
  }

  @MainActor
  @Test func `reads the hour from original measurements even when the day has been downsampled`() async throws {
    let calendar = Calendar.current
    let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: .now))
    let day = try #require(calendar.dateInterval(of: .day, for: yesterday))
    let hour = try #require(calendar.dateInterval(of: .hour, for: day.start.addingTimeInterval(7200)))
    let samples = (0 ..< 360).map { minute in
      measurement(.heartRate, value: 80, date: day.start.addingTimeInterval(Double(minute * 60)))
    }
    let reader = MockAppleHealthReader(samples: samples)
    let sync = SynchronizeHealthHistory(appleHealth: reader, store: HealthHistoryStore(inMemory: true))
    let refresh = RefreshTodayHealth(appleHealth: reader, synchronizeHealthHistory: sync)
    var token: UUID?
    await refresh(isCurrent: { true }, onUpdate: { update in
      if case let .measurement(.heartRate, _, verification) = update {
        token = verification
      }
    })
    let verification = try #require(token)
    let queries = await reader.queryStarts.count
    let dayPoints = try await refresh.readTimeline(for: .heartRate, in: day, verification: verification)
    let hourPoints = try await refresh.readTimeline(for: .heartRate, in: hour, verification: verification)
    let expected = samples.filter { $0.endDate >= hour.start && $0.endDate < hour.end }.map {
      IntradayHealthPoint(date: $0.endDate, value: $0.value)
    }
    #expect(hourPoints == expected)
    #expect(hourPoints.count == 60)
    #expect(dayPoints.filter { $0.date >= hour.start && $0.date < hour.end }.count < hourPoints.count)
    #expect(await reader.queryStarts.count == queries)
  }
}
