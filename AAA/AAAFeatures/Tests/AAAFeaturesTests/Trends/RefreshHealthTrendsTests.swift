@testable import AACUseCases
import AAMStorages
import AANModels
import Foundation
import Testing

struct RefreshHealthTrendsTests {
  @Test func `uses 30 civil days across midnight DST and excludes future samples`() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Santiago"))
    let first = try Date("2026-08-08T04:00:00Z", strategy: .iso8601)
    let now = try Date("2026-09-06T15:00:00Z", strategy: .iso8601)
    let tomorrow = try Date("2026-09-07T03:00:00Z", strategy: .iso8601)
    let projection = try #require(ReadDailyHealthTrend(now: now, calendar: calendar, retentionDays: nil))
    let store = HealthHistoryStore(inMemory: true)
    let interval = DateInterval(start: first.addingTimeInterval(-60), end: tomorrow)

    let readings = (0 ..< 600).map { index in
      measurement(
        .heartRate, value: index.isMultiple(of: 2) ? 60 : 100, date: first.addingTimeInterval(Double(index))
      )
    } + [
      measurement(.heartRate, value: 120, date: first.addingTimeInterval(-1)),
      measurement(.heartRate, value: 120, date: now),
    ]
    try await seed(readings, for: .heartRate, in: interval, store: store)
    let days = try await projection(.heartRate, from: store)

    #expect(projection.interval.start == first)
    #expect(projection.interval.end == tomorrow)
    #expect(calendar.dateComponents([.day], from: first, to: tomorrow).day == 30)
    let day = try #require(days.first)
    #expect(days.count == 1)
    #expect(day.day == first)
    #expect(abs(day.value - 80) < 0.000001)
  }

  @Test func `uses each day's newest usable HRV sample to choose comparable measurements`() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let now = try Date("2026-09-06T12:00:00Z", strategy: .iso8601)
    let today = calendar.startOfDay(for: now)
    let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
    let store = HealthHistoryStore(inMemory: true)
    let metric = TodayHealthMetric.heartRateVariability
    let projection = try #require(ReadDailyHealthTrend(now: now, calendar: calendar, retentionDays: nil))
    let readings = [
      measurement(metric, value: 40, date: today.addingTimeInterval(10 * 3600), duration: 60),
      measurement(metric, value: 60, date: today.addingTimeInterval(11 * 3600), duration: 60),
      measurement(metric, value: 150, date: today.addingTimeInterval(10 * 3600), duration: 60, source: "phone"),
      measurement(metric, value: 150, date: today.addingTimeInterval(10 * 3600), duration: 60, device: "phone"),
      measurement(metric, value: 150, date: today.addingTimeInterval(10 * 3600), duration: 15),
      measurement(metric, value: 150, date: today.addingTimeInterval(9 * 3600), duration: 60),
      measurement(metric, value: 20, date: yesterday.addingTimeInterval(20 * 3600), duration: 30, source: "phone"),
      measurement(metric, value: 40, date: yesterday.addingTimeInterval(21 * 3600), duration: 30, source: "phone"),
    ]
    try await seed(readings, for: metric, in: DateInterval(start: yesterday, end: now), store: store)

    #expect(try await projection(metric, from: store) == [
      DailyHealthValue(day: yesterday, value: 30),
      DailyHealthValue(day: today, value: 50),
    ])
  }

  @Test func `checks read access before reuse and limits verified points to requested retention`() async throws {
    let oxygen = TodayHealthMetric.bloodOxygen
    let calendar = Calendar.current
    let now = Date.now
    let candidate = now.addingTimeInterval(-60)
    let recent = max(candidate, calendar.startOfDay(for: candidate).addingTimeInterval(2))
    let older = try #require(calendar.date(byAdding: .day, value: -2, to: recent))
    let reader = MockAppleHealthReader(
      samples: [
        measurement(oxygen, value: 0.96, date: older),
        measurement(oxygen, value: 0.97, date: recent.addingTimeInterval(-1)),
        measurement(oxygen, value: 0.98, date: recent),
      ],
      needsAuthorizationRequest: true,
      failedMetric: .respiratoryRate
    )
    let store = HealthHistoryStore(inMemory: true)
    let sync = SynchronizeHealthHistory(appleHealth: reader, store: store)
    let refresh = RefreshHealthTrends(appleHealth: reader, synchronizeHealthHistory: sync)

    await #expect(throws: RefreshHealthTrends.LoadError.needsAuthorization) {
      try await refresh()
    }
    #expect(await reader.authorizationRequests == 0)
    #expect(await reader.queryStarts.isEmpty)

    let connected = try await refresh(requestAuthorization: true)
    let recentPoint = DailyHealthValue(day: calendar.startOfDay(for: recent), value: 0.98)
    #expect(connected.series[oxygen] == .readings([
      DailyHealthValue(day: calendar.startOfDay(for: older), value: 0.96),
      recentPoint,
    ]))
    #expect(connected.series[.respiratoryRate] == .failed)
    #expect(connected.series[.restingHeartRate] == .readings([]))

    let shortened = try await refresh(reusingLatest: true, retentionDays: 1)
    #expect(shortened.series[oxygen] == .readings([recentPoint]))

    await reader.requireAuthorization()
    await #expect(throws: RefreshHealthTrends.LoadError.needsAuthorization) {
      try await refresh(reusingLatest: true)
    }
    await #expect(throws: HealthHistoryStore.StoreError.unverified) {
      try await store.readings(for: oxygen, in: connected.interval)
    }
  }

  @Test func `publishes the current verified baseline and omits one with insufficient days`() async throws {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    let days = try (1 ... 21).map { offset in
      let day = try #require(calendar.date(byAdding: .day, value: -offset, to: today))
      return try #require(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day))
    }
    let variability = days.map { date in
      measurement(.heartRateVariability, value: 45, date: date, duration: 60)
    }
    let samples = days.enumerated().map { index, date in
      measurement(.restingHeartRate, value: 51 + Double(index), date: date)
    } + variability.dropLast()
    let reader = MockAppleHealthReader(samples: samples)
    let store = HealthHistoryStore(inMemory: true)
    let sync = SynchronizeHealthHistory(appleHealth: reader, store: store)
    let refresh = RefreshHealthTrends(appleHealth: reader, synchronizeHealthHistory: sync)

    let snapshot = try await refresh()
    let expected = try #require(HealthBaselineRange(lowerBound: 53, median: 61, upperBound: 69))
    #expect(snapshot.baselines == [.restingHeartRate: expected])
    let persisted = try await store.baselineInput(for: .restingHeartRate, in: snapshot.interval).baseline
    #expect(persisted?.p10 == expected.lowerBound)
    #expect(persisted?.p50 == expected.median)
    #expect(persisted?.p90 == expected.upperBound)

    let pendingShorterRetention = try await refresh(reusingLatest: true, retentionDays: 22)
    #expect(pendingShorterRetention.baselines.isEmpty)

    await sync.setRetentionDays(22)
    await reader.replaceSamples(for: .heartRateVariability, with: variability)
    let verifiedShorterRetention = try await refresh(retentionDays: 22)
    let variabilityRange = try #require(HealthBaselineRange(lowerBound: 45, median: 45, upperBound: 45))
    #expect(verifiedShorterRetention.baselines == [
      .restingHeartRate: expected,
      .heartRateVariability: variabilityRange,
    ])
  }

  private func seed(
    _ samples: [HealthMeasurement],
    for metric: TodayHealthMetric,
    in interval: DateInterval,
    store: HealthHistoryStore
  ) async throws {
    let reconciliation = try await store.beginReconciliation(
      for: metric, retainingFrom: interval.start, queryStart: interval.start
    )
    let generation = reconciliation.generation
    let anchor = Data([1])
    let batch = HealthSampleBatch(
      measurements: samples, seenSampleIDs: samples.map(\.healthKitUUID), deletedSampleIDs: [], anchor: anchor
    )
    try await store.apply(batch, for: metric, generation: generation, expectedAnchor: nil, retainingIn: interval)
    let drained = HealthSampleBatch(measurements: [], seenSampleIDs: [], deletedSampleIDs: [], anchor: anchor)
    try await store.apply(drained, for: metric, generation: generation, expectedAnchor: anchor, retainingIn: interval)
    try await store.finishReconciliation(for: metric, generation: generation, retainingIn: interval)
  }
}
