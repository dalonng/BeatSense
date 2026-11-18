@testable import AAAFeatures
import AACUseCases
import AAMStorages
import AANModels
import Foundation
import Testing

@MainActor
struct HeartRateVariabilityHistoryTests {
  private let metric = TodayHealthMetric.heartRateVariability
  private let calendar = Calendar.current

  @Test func `retains a qualifying period after backfill and replaces it after a deletion`() async throws {
    let today = calendar.startOfDay(for: .now)
    let original = try history(21, endingAt: today, hour: 4, value: 50)
    let extra = try history(21, endingAt: today, hour: 5, value: 70)
    let alternate = try history(26, endingAt: today, hour: 2, value: 90)
    let reader = MockAppleHealthReader(samples: original)
    let store = HealthHistoryStore(inMemory: true)
    let sync = SynchronizeHealthHistory(appleHealth: reader, store: store)
    let model = TodayViewModel(refreshTodayHealth: .init(appleHealth: reader, synchronizeHealthHistory: sync))
    await model.load(id: model.loadID)
    let first = try await baseline(in: store)
    #expect(first.referencePeriod == 2)
    #expect(first.p50 == 50)

    await reader.replaceSamples(for: metric, with: original + extra + alternate)
    model.reload()
    await model.load(id: model.loadID)
    let retained = try await baseline(in: store)
    #expect(retained.referencePeriod == first.referencePeriod)
    #expect(retained.validDayCount == 21)
    #expect(retained.p50 == 60)

    let remaining = Array(original.dropLast()) + Array(extra.dropLast())
    await reader.replaceSamples(for: metric, with: remaining + alternate)
    model.reload()
    await model.load(id: model.loadID)
    let replacement = try await baseline(in: store)
    #expect(replacement.referencePeriod == 1)
    #expect(replacement.validDayCount == 26)
    #expect(replacement.p50 == 90)
  }

  @Test func `shows the latest HRV separately from the comparable daily median`() async throws {
    let now = Date.now
    let today = calendar.startOfDay(for: now)
    let past = try history(21, endingAt: today, hour: 0, value: 40)
    let latestDate = today.addingTimeInterval(min(1, now.timeIntervalSince(today) / 2))
    let current = [
      measurement(metric, value: 50, date: today, duration: 60),
      measurement(metric, value: 70, date: latestDate, duration: 60),
    ]
    let reader = MockAppleHealthReader(samples: past + current)
    let sync = SynchronizeHealthHistory(appleHealth: reader, store: HealthHistoryStore(inMemory: true))
    let model = TodayViewModel(refreshTodayHealth: .init(appleHealth: reader, synchronizeHealthHistory: sync))

    await model.load(id: model.loadID)

    #expect(model.measurement(for: metric) == .baselineSample(
      value: 70, date: latestDate, referenceMedian: 60, status: .compared(difference: 20, position: .aboveRange)
    ))
  }

  private func history(_ days: Int, endingAt today: Date, hour: Int, value: Double) throws -> [HealthMeasurement] {
    try (1 ... days).map { offset in
      let day = try #require(calendar.date(byAdding: .day, value: -offset, to: today))
      let date = try #require(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day))
      return measurement(metric, value: value, date: date, duration: 60)
    }
  }

  private func baseline(in store: HealthHistoryStore) async throws -> PersonalBaseline {
    let input = try await store.baselineInput(for: metric, in: DateInterval(start: .distantPast, end: .distantFuture))
    return try #require(input.baseline)
  }
}
