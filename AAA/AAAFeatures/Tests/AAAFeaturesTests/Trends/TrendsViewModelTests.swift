@testable import AAAFeatures
import AACUseCases
import AAMStorages
import AANModels
import Foundation
import Testing

@MainActor
struct TrendsViewModelTests {
  private let retentionDays = SynchronizeHealthHistory.defaultRetentionDays

  @Test func `returning to the tab reuses the window snapshot until it is invalidated`() async throws {
    let reader = MockAppleHealthReader()
    let app = makeApp(reader)
    let model = app.trends
    let initial = try #require(model.loadID)
    await model.load(id: initial, retentionDays: retentionDays)
    let previous = try #require(snapshot(in: model))
    let queries = await reader.queryStarts.count
    #expect(model.loadID == nil)
    #expect(!model.isLoading)

    model.cancelConnection()
    await reader.requireAuthorization()
    #expect(app.trends === model)
    await app.trends.load(id: initial, retentionDays: retentionDays)
    #expect(snapshot(in: model) == previous)
    #expect(await reader.queryStarts.count == queries)

    model.revalidate()
    #expect(snapshot(in: model) == nil)
    let next = try #require(model.loadID)
    #expect(next != initial)
    await model.load(id: next, retentionDays: retentionDays)
    guard case .needsConnection = model.phase else {
      Issue.record("Expected access to be checked again after invalidation.")
      return
    }
    #expect(model.loadID == nil)
    #expect(!model.isLoading)
  }

  @Test func `a verified health change updates the visible snapshot in place`() async throws {
    let date = Date.now.addingTimeInterval(-60)
    let reader = MockAppleHealthReader(samples: [measurement(.bloodOxygen, value: 0.96, date: date)])
    let app = makeApp(reader)
    let model = app.trends
    let initial = try #require(model.loadID)
    await model.load(id: initial, retentionDays: retentionDays)
    let previous = try #require(snapshot(in: model))
    let day = previous.calendar.startOfDay(for: date)
    #expect(previous.series[.bloodOxygen] == .readings([DailyHealthValue(day: day, value: 0.96)]))

    // The shared foreground observer publishes the change after the mirror has finished updating.
    await reader.replaceSamples(for: .bloodOxygen, with: [measurement(.bloodOxygen, value: 0.99, date: date)])
    await app.refreshTodayHealth(isCurrent: { true }, onUpdate: { _ in })
    let queries = await reader.queryStarts.count
    model.receiveHealthChange()
    #expect(snapshot(in: model) == previous)
    #expect(model.isLoading)
    let next = try #require(model.loadID)
    #expect(next != initial)
    await model.load(id: next, retentionDays: retentionDays)

    let updated = try #require(snapshot(in: model))
    #expect(updated.series[.bloodOxygen] == .readings([DailyHealthValue(day: day, value: 0.99)]))
    #expect(await reader.queryStarts.count == queries)
    #expect(model.loadID == nil)
  }

  @Test func `a cancelled refresh keeps its snapshot and can resume with the pending load ID`() async throws {
    let reader = MockAppleHealthReader()
    let model = makeApp(reader).trends
    let initial = try #require(model.loadID)
    await model.load(id: initial, retentionDays: retentionDays)
    let previous = try #require(snapshot(in: model))
    let sample = measurement(.heartRate, value: 82, date: .now.addingTimeInterval(-60))
    await reader.replaceSamples(for: .heartRate, with: [sample])
    await reader.suspendNextHeartRateQuery()
    model.reload()
    let pending = try #require(model.loadID)
    let load = Task { await model.load(id: pending, retentionDays: retentionDays) }
    await reader.waitForSuspendedQuery()
    load.cancel()
    model.cancelConnection()
    await reader.resumeSuspendedQuery()
    await load.value

    #expect(model.loadID == pending)
    #expect(snapshot(in: model) == previous)
    await model.load(id: pending, retentionDays: retentionDays)
    let updated = try #require(snapshot(in: model))
    let day = updated.calendar.startOfDay(for: sample.endDate)
    #expect(updated.series[.heartRate] == .readings([DailyHealthValue(day: day, value: 82)]))
    #expect(model.loadID == nil)
  }

  @Test func `hiding verified readings prevents an outstanding refresh from restoring them`() async throws {
    let reader = MockAppleHealthReader()
    let model = makeApp(reader).trends
    let initial = try #require(model.loadID)
    await model.load(id: initial, retentionDays: retentionDays)
    #expect(snapshot(in: model) != nil)
    await reader.suspendNextHeartRateQuery()
    model.reload()
    let old = try #require(model.loadID)
    let load = Task { await model.load(id: old, retentionDays: retentionDays) }
    await reader.waitForSuspendedQuery()

    model.hideReadings()
    let next = model.loadID
    #expect(next != nil && next != old)
    #expect(snapshot(in: model) == nil)
    await reader.resumeSuspendedQuery()
    await load.value
    #expect(snapshot(in: model) == nil)
    #expect(model.loadID == next)
    #expect(model.isLoading)
  }

  private func makeApp(_ reader: MockAppleHealthReader) -> AppViewModel {
    let sync = SynchronizeHealthHistory(appleHealth: reader, store: HealthHistoryStore(inMemory: true))
    return AppViewModel(appleHealth: reader, synchronizeHealthHistory: sync)
  }

  private func snapshot(in model: TrendsViewModel) -> RefreshHealthTrends.Snapshot? {
    guard case let .ready(snapshot) = model.phase else { return nil }
    return snapshot
  }
}
