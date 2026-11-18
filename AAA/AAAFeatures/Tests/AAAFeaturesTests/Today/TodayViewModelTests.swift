@testable import AAAFeatures
import AACUseCases
import AAMServices
import AAMStorages
import AANModels
import Foundation
import Observation
import Testing

@MainActor
struct TodayViewModelTests {
  @Test func `initial load offers connection without requesting authorization`() async {
    let reader = MockAppleHealthReader(needsAuthorizationRequest: true)
    let model = makeModel(appleHealth: reader)

    await model.load(id: model.loadID)

    #expect(model.phase == .needsConnection)
    #expect(await reader.authorizationRequests == 0)
    #expect(await reader.queryStarts.isEmpty)
    #expect(await reader.sleepQueries.isEmpty)

    model.connect()
    await model.load(id: model.loadID)

    #expect(await reader.authorizationRequests == 1)
    #expect(await reader.requestedScopes == [.all])
    #expect(await reader.queryStarts.count == TodayHealthMetric.allCases.count)
    #expect(await reader.sleepQueries.count == 1)
    #expect(model.phase == .ready)
  }

  @Test func `no visible samples become empty`() async throws {
    let reader = MockAppleHealthReader()
    let model = makeModel(appleHealth: reader)
    let calendar = Calendar.current
    let earliest = try #require(calendar.date(byAdding: .day, value: -90, to: .now))

    await model.load(id: model.loadID)

    #expect(model.sleepState == .empty)
    for metric in TodayHealthMetric.allCases {
      let expected: TodayViewModel.MeasurementState = switch metric {
      case .restingHeartRate, .heartRateVariability:
        .baselineSample(value: nil, date: nil, referenceMedian: nil, status: .building)
      default:
        .empty
      }
      #expect(model.measurement(for: metric) == expected)
    }
    let latest = try #require(calendar.date(byAdding: .day, value: -90, to: .now))
    let queryStarts = await reader.queryStarts
    let firstStart = try #require(queryStarts.first)
    #expect(queryStarts.count == TodayHealthMetric.allCases.count)
    #expect(queryStarts.allSatisfy { $0 == firstStart })
    #expect(earliest ... latest ~= firstStart)
    #expect(await reader.authorizationRequests == 0)
  }

  @Test func `one failure does not hide or prevent saving other measurements`() async throws {
    let date = Date.now.addingTimeInterval(-2)
    let oxygen = measurement(.bloodOxygen, value: 0.98, date: date)
    let restingRate = measurement(.restingHeartRate, value: 62, date: date.addingTimeInterval(-3600))
    let variability = measurement(.heartRateVariability, value: 48, date: date, duration: 60)
    let reader = MockAppleHealthReader(
      samples: [oxygen, restingRate, variability],
      failedMetric: .respiratoryRate
    )
    let store = HealthHistoryStore(inMemory: true)
    let model = makeModel(appleHealth: reader, healthStore: store)

    await model.load(id: model.loadID)

    #expect(model.measurement(for: .heartRate) == .empty)
    #expect(model.measurement(for: .bloodOxygen) == .sample(value: 0.98, date: date))
    #expect(model.measurement(for: .respiratoryRate) == .failed)
    #expect(model.measurement(for: .restingHeartRate) == .baselineSample(
      value: 62,
      date: restingRate.endDate,
      referenceMedian: nil,
      status: .building
    ))
    #expect(model.measurement(for: .heartRateVariability) == .baselineSample(
      value: 48,
      date: date,
      referenceMedian: Calendar.current.isDateInToday(date) ? 48 : nil,
      status: .building
    ))
    #expect(!model.isLoading)
    #expect(try await store.readings(for: .bloodOxygen, in: allDates) == [oxygen])
    #expect(try await store.readings(for: .restingHeartRate, in: allDates) == [restingRate])
    #expect(try await store.readings(for: .heartRateVariability, in: allDates) == [variability])
  }

  @Test func `a canceled view load does not deliver its suspended reading`() async {
    let heartRate = measurement(.heartRate, value: 80, date: .now.addingTimeInterval(-2))
    let reader = MockAppleHealthReader(samples: [heartRate])
    await reader.suspendNextHeartRateQuery()
    let model = makeModel(appleHealth: reader)
    let id = model.loadID
    let load = Task { await model.load(id: id) }
    await reader.waitForSuspendedQuery()

    load.cancel()
    await reader.resumeSuspendedQuery()
    await load.value

    #expect(model.measurement(for: .heartRate) == .loading)
    #expect(!model.isLoading)
  }

  @Test func `a deletion removes the stored sample and clears the card`() async throws {
    let store = HealthHistoryStore(inMemory: true)
    let sample = measurement(.bloodOxygen, value: 0.97, date: .now.addingTimeInterval(-2))
    let reader = MockAppleHealthReader(samples: [sample])
    let model = makeModel(appleHealth: reader, healthStore: store)

    await model.load(id: model.loadID)
    #expect(try await store.readings(for: .bloodOxygen, in: allDates) == [sample])

    await reader.replaceSamples(for: .bloodOxygen, with: [])
    model.reload()
    await model.load(id: model.loadID)
    #expect(model.measurement(for: .bloodOxygen) == .empty)
    #expect(try await store.readings(for: .bloodOxygen, in: allDates).isEmpty)
  }

  @Test func `refresh keeps current readings and only invalidates changed cards`() async {
    let date = Date.now.addingTimeInterval(-2)
    let heartRate = measurement(.heartRate, value: 70, date: date)
    let oxygen = measurement(.bloodOxygen, value: 0.97, date: date)
    let reader = MockAppleHealthReader(samples: [heartRate, oxygen])
    let model = makeModel(appleHealth: reader)
    await model.load(id: model.loadID)
    let previous = model.measurement(for: .heartRate)
    guard case let .heartRate(summary) = previous else {
      Issue.record("Expected the imported heart rate sample to be displayed.")
      return
    }
    #expect(summary.latest.beatsPerMinute == 70)
    await reader.replaceSamples(for: .bloodOxygen, with: [measurement(.bloodOxygen, value: 0.99, date: date)])
    await reader.suspendNextHeartRateQuery()

    await confirmation("Unchanged page and cards", expectedCount: 0) { invalidated in
      withObservationTracking {
        _ = model.phase
        _ = model.measurement(for: .heartRate)
        _ = model.measurement(for: .heartRateVariability)
      } onChange: {
        invalidated()
      }

      model.reload()
      #expect(model.phase == .ready)
      #expect(model.measurement(for: .bloodOxygen) == .sample(value: 0.97, date: date))
      let load = Task { await model.load(id: model.loadID) }
      await reader.waitForSuspendedQuery()
      #expect(model.isLoading)
      #expect(model.measurement(for: .heartRate) == previous)
      await reader.resumeSuspendedQuery()
      await load.value

      #expect(!model.isLoading)
      #expect(model.measurement(for: .heartRate) == previous)
      #expect(model.measurement(for: .bloodOxygen) == .sample(value: 0.99, date: date))
    }
  }

  @Test func `a refresh that requires authorization removes previous readings`() async {
    let sample = measurement(.bloodOxygen, value: 0.97, date: .now.addingTimeInterval(-2))
    let reader = MockAppleHealthReader(samples: [sample])
    let model = makeModel(appleHealth: reader)
    await model.load(id: model.loadID)

    await reader.requireAuthorization()
    model.reload()
    await model.load(id: model.loadID)

    #expect(model.phase == .needsConnection)
    #expect(model.measurement(for: .bloodOxygen) == .loading)
    #expect(model.verifiedRefresh(for: .bloodOxygen) == nil)
    #expect(!model.isLoading)
    #expect(await reader.authorizationRequests == 0)
  }

  @Test func `day chart refreshes after an earlier reading is deleted while the card stays the same`() async throws {
    let day = try #require(Calendar.current.dateInterval(of: .day, for: Date.now.addingTimeInterval(-86400)))
    let earlier = measurement(.bloodOxygen, value: 0.96, date: day.start.addingTimeInterval(60))
    let latest = measurement(.bloodOxygen, value: 0.98, date: day.start.addingTimeInterval(120))
    let reader = MockAppleHealthReader(samples: [earlier, latest])
    let model = makeModel(appleHealth: reader)
    await model.load(id: model.loadID)
    let original = try #require(model.verifiedRefresh(for: .bloodOxygen))
    let card = model.measurement(for: .bloodOxygen)
    #expect(try await model.readTimeline(for: .bloodOxygen, in: day, refresh: original).count == 2)

    await reader.replaceSamples(for: .bloodOxygen, with: [latest])
    model.reload()
    await model.load(id: model.loadID)
    let refresh = try #require(model.verifiedRefresh(for: .bloodOxygen))
    #expect(model.measurement(for: .bloodOxygen) == card)
    #expect(refresh != original)
    #expect(try await model.readTimeline(for: .bloodOxygen, in: day, refresh: refresh) == [
      IntradayHealthPoint(date: latest.endDate, value: latest.value),
    ])
    await #expect(throws: CancellationError.self) {
      try await model.readTimeline(for: .bloodOxygen, in: day, refresh: original)
    }
  }

  @Test func `only the latest foreground change schedules a refresh`() async throws {
    let reader = MockAppleHealthReader()
    let model = makeModel(appleHealth: reader)
    let initialLoadID = model.loadID
    await model.load(id: initialLoadID)

    model.receiveHealthChange()
    let earlierChange = try #require(model.healthChangeID)
    model.receiveHealthChange()
    let latestChange = try #require(model.healthChangeID)
    #expect(earlierChange != latestChange)

    await model.refreshAfterHealthChange(id: earlierChange, debounce: .zero)
    #expect(model.loadID == initialLoadID)
    await model.refreshAfterHealthChange(id: latestChange, debounce: .zero)
    #expect(model.loadID != initialLoadID)
    #expect(model.healthChangeID == nil)
  }

  @Test(arguments: [false, true]) func `changes during a load queue one refresh unless observation stops`(
    stopObservation: Bool
  ) async {
    let reader = MockAppleHealthReader()
    await reader.suspendNextHeartRateQuery()
    let model = makeModel(appleHealth: reader)
    let initialLoadID = model.loadID
    let load = Task { await model.load(id: initialLoadID) }
    await reader.waitForSuspendedQuery()

    for _ in 0 ..< 3 {
      model.receiveHealthChange()
      if let changeID = model.healthChangeID {
        await model.refreshAfterHealthChange(id: changeID, debounce: .zero)
      } else {
        Issue.record("The in-flight refresh should accept changes.")
      }
    }
    #expect(model.loadID == initialLoadID)
    if stopObservation {
      model.discardPendingHealthRefresh()
    }
    await reader.resumeSuspendedQuery()
    await load.value

    if stopObservation {
      #expect(model.loadID == initialLoadID)
    } else {
      #expect(model.loadID != initialLoadID)
      let followUp = model.loadID
      await model.load(id: followUp)
      #expect(model.loadID == followUp)
    }
  }
}

@MainActor
struct TodaySleepViewModelTests {
  @Test func `new sleep stages update a visible card with unchanged times`() async throws {
    let end = Date.now
    let interval = DateInterval(start: end.addingTimeInterval(-3600), end: end)
    let reader = MockAppleHealthReader()
    let model = makeModel(appleHealth: reader)
    await reader.setSleepSamples([SleepSample(interval: interval, state: .asleep)])
    await model.load(id: model.loadID)
    #expect(model.sleepState == .summary(TodaySleepSummary(
      startDate: interval.start, endDate: end, stageDurations: [.asleep: 3600]
    )))

    await reader.setSleepSamples([
      SleepSample(interval: interval, state: .asleep),
      SleepSample(interval: interval, state: .deep),
    ])
    let previousLoad = model.loadID
    model.receiveHealthChange()
    let change = try #require(model.healthChangeID)
    await model.refreshAfterHealthChange(id: change, debounce: .zero)
    #expect(model.loadID != previousLoad)
    await model.load(id: model.loadID)
    #expect(model.sleepState == .summary(TodaySleepSummary(
      startDate: interval.start, endDate: end, stageDurations: [.deep: 3600]
    )))
  }

  @Test func `adding sleep to an existing installation leaves measurements and Trends available`() async throws {
    let end = Date.now.addingTimeInterval(-1)
    let oxygen = measurement(.bloodOxygen, value: 0.97, date: end)
    let reader = MockAppleHealthReader(samples: [oxygen], needsSleepAuthorization: true)
    let sync = SynchronizeHealthHistory(appleHealth: reader, store: HealthHistoryStore(inMemory: true))
    let model = TodayViewModel(refreshTodayHealth: RefreshTodayHealth(
      appleHealth: reader,
      synchronizeHealthHistory: sync
    ))
    await model.load(id: model.loadID)
    #expect(model.phase == .ready)
    #expect(model.measurement(for: .bloodOxygen) == .sample(value: 0.97, date: end))
    #expect(model.sleepState == .needsConnection)
    #expect(await reader.sleepQueries.isEmpty)
    _ = try await RefreshHealthTrends(appleHealth: reader, synchronizeHealthHistory: sync)(reusingLatest: true)
    #expect(await reader.requestedScopes.isEmpty)

    model.connectSleep()
    await model.load(id: model.loadID)
    #expect(await reader.requestedScopes == [.sleep])
    #expect(model.sleepState == .empty)
    #expect(model.measurement(for: .bloodOxygen) == .sample(value: 0.97, date: end))
  }

  @Test func `moving to the background discards a pending sleep reading`() async {
    let reader = MockAppleHealthReader()
    await reader.suspendNextSleepQuery()
    let model = makeModel(appleHealth: reader)
    let load = Task { await model.load(id: model.loadID) }
    await reader.waitForSuspendedQuery()
    model.hideReadings()
    await reader.resumeSuspendedQuery()
    await load.value
    #expect(model.sleepState == .loading)
    #expect(!model.isLoading)
  }

  @Test func `sleep refresh handles query failure, deletion and background privacy`() async {
    let end = Date.now
    let interval = DateInterval(start: end.addingTimeInterval(-3600), end: end)
    let reader = MockAppleHealthReader(samples: [measurement(.bloodOxygen, value: 0.98, date: end)])
    let model = makeModel(appleHealth: reader)
    await reader.failSleepQuery()
    await model.load(id: model.loadID)
    #expect(model.sleepState == .failed)
    #expect(model.measurement(for: .bloodOxygen) == .sample(value: 0.98, date: end))

    await reader.setSleepSamples([SleepSample(interval: interval, state: .asleep)])
    model.reload()
    await model.load(id: model.loadID)
    #expect(model.sleepState == .summary(TodaySleepSummary(
      startDate: interval.start, endDate: end, stageDurations: [.asleep: 3600]
    )))

    model.hideReadings()
    #expect(model.sleepState == .loading)
    await reader.setSleepSamples([])
    model.revalidateReadings()
    await model.load(id: model.loadID)
    #expect(model.sleepState == .empty)
  }
}

@MainActor
struct TodayHealthPersistenceTests {
  @Test(arguments: [TodayHealthMetric.restingHeartRate, .heartRateVariability])
  func `persists baseline quantiles without a current reading`(metric: TodayHealthMetric) async throws {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    let samples = try (1 ... 21).map { day in
      let start = try #require(calendar.date(byAdding: .day, value: -day, to: today))
      let date = try #require(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: start))
      return measurement(metric, value: Double(49 + day), date: date, duration: 60)
    }
    let reader = MockAppleHealthReader(samples: samples)
    let store = HealthHistoryStore(inMemory: true)
    let model = makeModel(appleHealth: reader, healthStore: store)

    await model.load(id: model.loadID)

    let input = try await store.baselineInput(for: metric, in: allDates)
    let baseline = try #require(input.baseline)
    #expect(baseline.p10 == 52)
    #expect(baseline.p50 == 60)
    #expect(baseline.p90 == 68)
    #expect(baseline.validDayCount == 21)
    #expect(baseline.windowEnd == today)
    #expect(model.measurement(for: metric) == .baselineSample(
      value: 50,
      date: samples.first?.endDate,
      referenceMedian: nil,
      status: .noCurrentReading
    ))
  }

  @Test(arguments: [30, 45]) func `retention range is independent from the Today display window`(
    retentionDays: Int
  ) async throws {
    let date = try #require(Calendar.current.date(byAdding: .day, value: -36, to: .now))
    let sample = measurement(.bloodOxygen, value: 0.97, date: date)
    let reader = MockAppleHealthReader(samples: [sample])
    let store = HealthHistoryStore(inMemory: true)
    let model = makeModel(appleHealth: reader, healthStore: store, retentionDays: retentionDays)

    await model.load(id: model.loadID)

    #expect(model.measurement(for: .bloodOxygen) == .empty)
    let retained = try await store.readings(for: .bloodOxygen, in: allDates)
    #expect(retained == (retentionDays == 30 ? [] : [sample]))
  }

  @Test func `retention changes backfill and expire samples under the same coordinator`() async throws {
    let date = try #require(Calendar.current.date(byAdding: .day, value: -60, to: .now))
    let sample = measurement(.bloodOxygen, value: 0.97, date: date)
    let reader = MockAppleHealthReader(samples: [sample])
    let store = HealthHistoryStore(inMemory: true)
    let sync = SynchronizeHealthHistory(appleHealth: reader, store: store, retentionDays: 30)
    let model = TodayViewModel(refreshTodayHealth: RefreshTodayHealth(
      appleHealth: reader,
      synchronizeHealthHistory: sync
    ))

    await model.load(id: model.loadID)
    #expect(try await store.readings(for: .bloodOxygen, in: allDates).isEmpty)

    await sync.setRetentionDays(90)
    model.reload()
    await model.load(id: model.loadID)
    #expect(try await store.readings(for: .bloodOxygen, in: allDates) == [sample])

    await sync.setRetentionDays(30)
    model.reload()
    await model.load(id: model.loadID)
    #expect(try await store.readings(for: .bloodOxygen, in: allDates).isEmpty)
  }

  @Test func `a narrower HealthKit authorization window removes previously visible measurements`() async throws {
    let now = Date.now
    let old = measurement(.bloodOxygen, value: 0.97, date: now.addingTimeInterval(-3600))
    let recent = measurement(.bloodOxygen, value: 0.99, date: now.addingTimeInterval(-2))
    let reader = MockAppleHealthReader(samples: [old, recent])
    let store = HealthHistoryStore(inMemory: true)
    let model = makeModel(appleHealth: reader, healthStore: store)
    await model.load(id: model.loadID)
    #expect(try await store.readings(for: .bloodOxygen, in: allDates) == [recent, old])

    await reader.limitHistory(for: .bloodOxygen, since: now.addingTimeInterval(-1800))
    model.reload()
    await model.load(id: model.loadID)
    #expect(try await store.readings(for: .bloodOxygen, in: allDates) == [recent])
  }
}

private let allDates = DateInterval(start: .distantPast, end: .distantFuture)

@MainActor
private func makeModel(
  appleHealth: any AppleHealthReading,
  healthStore: HealthHistoryStore = HealthHistoryStore(inMemory: true),
  retentionDays: Int = SynchronizeHealthHistory.defaultRetentionDays
) -> TodayViewModel {
  let sync = SynchronizeHealthHistory(appleHealth: appleHealth, store: healthStore, retentionDays: retentionDays)
  return TodayViewModel(
    refreshTodayHealth: RefreshTodayHealth(appleHealth: appleHealth, synchronizeHealthHistory: sync)
  )
}

func measurement(
  _ metric: TodayHealthMetric,
  value: Double,
  date: Date,
  duration: TimeInterval = 0,
  source: String = "watch",
  device: String? = "device"
) -> HealthMeasurement {
  HealthMeasurement(
    metric: metric,
    healthKitUUID: UUID(),
    ordinal: 0,
    startDate: date.addingTimeInterval(-duration),
    endDate: date,
    value: value,
    sourceIdentifier: source,
    deviceIdentifier: device
  )
}
