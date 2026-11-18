@testable import AAMStorages
import AANModels
import Foundation
import Testing

struct HealthHistoryStoreTests {
  private let interval = DateInterval(start: Date(timeIntervalSinceReferenceDate: 100), duration: 1000)

  @Test func `series rows are retained as separate readings and deleted by parent UUID`() async throws {
    let store = HealthHistoryStore(inMemory: true)
    let parent = UUID()
    let rows = [
      measurement(parent, ordinal: 0, at: 0),
      measurement(parent, ordinal: 1, at: 10),
      measurement(parent, ordinal: 2, at: 10),
      measurement(parent, ordinal: 3, at: 1000),
    ]
    let generation = try await importReadings(rows, into: store)
    #expect(try await store.readings(for: .heartRate, in: interval) == [rows[1], rows[2], rows[0]])
    #expect(try await store.readings(for: .heartRate, in: interval, limit: 1, offset: 1) == [rows[2]])

    try await store.apply(
      batch(rows, anchor: 2),
      for: .heartRate,
      generation: generation,
      expectedAnchor: Data([1]),
      retainingIn: interval
    )
    #expect(try await store.readings(for: .heartRate, in: interval).count == 3)

    let deletion = batch([], deleted: [parent], anchor: 3)
    try await store.apply(
      deletion,
      for: .heartRate,
      generation: generation,
      expectedAnchor: Data([2]),
      retainingIn: interval
    )
    #expect(try await store.readings(for: .heartRate, in: interval).isEmpty)
    #expect(try await store.checkpoint(for: .heartRate)?.anchor == Data([3]))
  }

  @Test func `reopening keeps the baseline and samples behind a fresh visibility check`() async throws {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer {
      do {
        try FileManager.default.removeItem(at: directory)
      } catch {
        Issue.record(error)
      }
    }

    let row = measurement(UUID(), at: 40, metric: .heartRateVariability)
    let baseline = makeBaseline()
    let originalRevision = try await saveBaseline(baseline, row: row, directory: directory)
    let store = HealthHistoryStore(directory: directory)
    #expect(try await store.checkpoint(for: .heartRateVariability)?.anchor == Data([1]))
    #expect(try await store.checkpoint(for: .heartRateVariability)?.isVerified == false)
    await #expect(throws: HealthHistoryStore.StoreError.unverified) {
      try await store.baselineInput(for: .heartRateVariability, in: interval)
    }

    let reconciliation = try await begin(.heartRateVariability, in: store)
    #expect(reconciliation.reusableSampleIDs == [row.healthKitUUID])
    try await store.apply(
      batch([], seen: [row.healthKitUUID], anchor: 2),
      for: .heartRateVariability,
      generation: reconciliation.generation,
      expectedAnchor: nil,
      retainingIn: interval
    )
    try await finish(
      .heartRateVariability,
      in: store,
      generation: reconciliation.generation,
      cursor: 2,
      window: interval
    )

    let input = try await store.baselineInput(for: .heartRateVariability, in: interval)
    #expect(input.revision == originalRevision)
    #expect(input.measurements == [row])
    #expect(input.baseline == baseline)
    #expect(try await store.personalBaseline(
      for: .heartRateVariability,
      window: interval,
      timeZoneID: "Europe/London",
      algorithmVersion: baseline.algorithmVersion
    ) ==
      nil)
    #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
  }

  @Test func `verification is scoped to the active generation and metric`() async throws {
    let store = HealthHistoryStore(inMemory: true)
    let row = measurement(UUID(), at: 50, metric: .heartRateVariability)
    let sibling = measurement(UUID(), at: 25, metric: .respiratoryRate)
    let oldGeneration = try await importReadings([row], into: store, metric: .heartRateVariability)
    _ = try await importReadings([sibling], into: store, metric: .respiratoryRate)
    let refresh = try await begin(.heartRateVariability, in: store)
    await #expect(throws: HealthHistoryStore.StoreError.superseded) {
      try await store.apply(
        batch([row], anchor: 2),
        for: .heartRateVariability,
        generation: oldGeneration,
        expectedAnchor: Data([1]),
        retainingIn: interval
      )
    }
    await #expect(throws: HealthHistoryStore.StoreError.unverified) {
      try await store.readings(for: .heartRateVariability, in: interval)
    }
    #expect(try await store.readings(for: .respiratoryRate, in: interval) == [sibling])

    await store.invalidateVerification(for: .heartRateVariability)
    await #expect(throws: HealthHistoryStore.StoreError.superseded) {
      try await store.finishReconciliation(
        for: .heartRateVariability,
        generation: refresh.generation,
        retainingIn: interval
      )
    }
    #expect(try await store.readings(for: .respiratoryRate, in: interval) == [sibling])
  }

  @Test func `completed reconciliation drops missing rows and their baseline`() async throws {
    let store = HealthHistoryStore(inMemory: true)
    let row = measurement(UUID(), at: 50, metric: .heartRateVariability)
    _ = try await importReadings([row], into: store, metric: .heartRateVariability)
    let input = try await store.baselineInput(for: .heartRateVariability, in: interval)
    #expect(try await store.saveBaseline(
      makeBaseline(),
      for: .heartRateVariability,
      expectedGeneration: input.generation,
      expectedRevision: input.revision
    ))

    let refresh = try await begin(.heartRateVariability, in: store)
    try await store.apply(
      batch([], anchor: 3),
      for: .heartRateVariability,
      generation: refresh.generation,
      expectedAnchor: nil,
      retainingIn: interval
    )
    try await store.finishReconciliation(
      for: .heartRateVariability,
      generation: refresh.generation,
      retainingIn: interval
    )
    #expect(try await store.readings(for: .heartRateVariability, in: interval).isEmpty)
    let emptyInput = try await store.baselineInput(for: .heartRateVariability, in: interval)
    #expect(emptyInput.baseline == nil)
    #expect(emptyInput.previousHRVReference == nil)
    #expect(try await store.saveBaseline(
      makeBaseline(),
      for: .heartRateVariability,
      expectedGeneration: refresh.generation,
      expectedRevision: input.revision
    ) ==
      false)
  }

  @Test func `a clipped series is fetched again as the upper bound advances`() async throws {
    let store = HealthHistoryStore(inMemory: true)
    let parent = UUID()
    let rows = [measurement(parent, ordinal: 0, at: 50), measurement(parent, ordinal: 1, at: 1000)]
    _ = try await importReadings(rows, into: store)
    let session = try await begin(.heartRate, in: store)
    #expect(session.reusableSampleIDs.isEmpty)

    let wider = DateInterval(start: interval.start, end: interval.end.addingTimeInterval(2))
    try await store.apply(
      batch(rows, anchor: 2),
      for: .heartRate,
      generation: session.generation,
      expectedAnchor: nil,
      retainingIn: wider
    )
    try await finish(.heartRate, in: store, generation: session.generation, cursor: 2, window: wider)
    #expect(try await store.readings(for: .heartRate, in: wider) == Array(rows.reversed()))

    let narrower = DateInterval(start: wider.start.addingTimeInterval(51), end: wider.end)
    try await store.prune(for: .heartRate, retainingIn: narrower, generation: session.generation)
    #expect(try await store.readings(for: .heartRate, in: wider) == [rows[1]])
    #expect(try await begin(.heartRate, in: store).reusableSampleIDs.isEmpty)
  }

  @Test func `a rejected batch leaves both samples and anchor intact`() async throws {
    let store = HealthHistoryStore(inMemory: true)
    let original = measurement(UUID(), at: 25)
    let duplicate = measurement(UUID(), at: 30)
    let generation = try await importReadings([original], into: store)
    let invalid = batch([duplicate, duplicate], deleted: [original.healthKitUUID], anchor: 2)

    await #expect(throws: HealthHistoryStore.StoreError.invalidBatch) {
      try await store.apply(
        invalid,
        for: .heartRate,
        generation: generation,
        expectedAnchor: Data([1]),
        retainingIn: interval
      )
    }
    #expect(try await store.readings(for: .heartRate, in: interval) == [original])
    #expect(try await store.checkpoint(for: .heartRate)?.anchor == Data([1]))
  }
}

extension HealthHistoryStoreTests {
  @Test(arguments: ["watch", "other watch"])
  func `retention cleanup clears statistics and keeps a reference only for a remaining device`(
    remainingDevice: String
  ) async throws {
    let store = HealthHistoryStore(inMemory: true)
    let metric = TodayHealthMetric.heartRateVariability
    let old = measurement(UUID(), at: 25, metric: metric)
    let latest = measurement(UUID(), at: 75, metric: metric, device: remainingDevice)
    _ = try await importReadings([old, latest], into: store, metric: metric)
    let previous = try await store.baselineInput(for: metric, in: interval)
    #expect(try await store.saveBaseline(
      makeBaseline(),
      for: metric,
      expectedGeneration: previous.generation,
      expectedRevision: previous.revision
    ))

    let cutoff = interval.start.addingTimeInterval(50)
    await store.invalidateVerification()
    try await store.pruneExpired(before: cutoff)
    let session = try await store.beginReconciliation(for: metric, retainingFrom: cutoff, queryStart: cutoff)
    #expect(session.reusableSampleIDs == [latest.healthKitUUID])

    let narrowed = DateInterval(start: cutoff, end: interval.end)
    try await store.apply(
      batch([], seen: [latest.healthKitUUID], anchor: 2),
      for: metric,
      generation: session.generation,
      expectedAnchor: nil,
      retainingIn: narrowed
    )
    try await finish(metric, in: store, generation: session.generation, cursor: 2, window: narrowed)

    let input = try await store.baselineInput(for: metric, in: interval)
    #expect(input.measurements == [latest])
    #expect(input.baseline == nil)
    #expect(input.revision != previous.revision)
    guard remainingDevice == "watch" else {
      #expect(input.previousHRVReference == nil)
      return
    }
    let reference = try #require(input.previousHRVReference)
    #expect(reference.referencePeriod == makeBaseline().referencePeriod)
    #expect(reference.validDayCount == 0)
    #expect(reference.p10 == nil && reference.p50 == nil && reference.p90 == nil)
  }
}

private extension HealthHistoryStoreTests {
  func begin(_ metric: TodayHealthMetric, in store: HealthHistoryStore) async throws -> HealthHistoryStore
    .Reconciliation
  {
    try await store.beginReconciliation(for: metric, retainingFrom: interval.start, queryStart: interval.start)
  }

  func importReadings(
    _ rows: [HealthMeasurement],
    into store: HealthHistoryStore,
    metric: TodayHealthMetric = .heartRate
  ) async throws -> UUID {
    let session = try await begin(metric, in: store)
    try await store.apply(
      batch(rows, anchor: 1),
      for: metric,
      generation: session.generation,
      expectedAnchor: nil,
      retainingIn: interval
    )
    try await finish(metric, in: store, generation: session.generation, cursor: 1, window: interval)
    return session.generation
  }

  func finish(
    _ metric: TodayHealthMetric,
    in store: HealthHistoryStore,
    generation: UUID,
    cursor: UInt8,
    window: DateInterval
  ) async throws {
    await #expect(throws: HealthHistoryStore.StoreError.incompleteReconciliation) {
      try await store.finishReconciliation(for: metric, generation: generation, retainingIn: window)
    }
    try await store.apply(
      batch([], anchor: cursor),
      for: metric,
      generation: generation,
      expectedAnchor: Data([cursor]),
      retainingIn: window
    )
    try await store.finishReconciliation(for: metric, generation: generation, retainingIn: window)
  }

  func saveBaseline(_ baseline: PersonalBaseline, row: HealthMeasurement, directory: URL) async throws -> UUID {
    let store = HealthHistoryStore(directory: directory)
    _ = try await importReadings([row], into: store, metric: row.metric)
    let input = try await store.baselineInput(for: row.metric, in: interval)
    #expect(try await store.saveBaseline(
      baseline,
      for: row.metric,
      expectedGeneration: input.generation,
      expectedRevision: input.revision
    ))
    return input.revision
  }

  func batch(
    _ rows: [HealthMeasurement],
    seen: [UUID]? = nil,
    deleted: [UUID] = [],
    anchor: UInt8
  ) -> HealthSampleBatch {
    HealthSampleBatch(
      measurements: rows,
      seenSampleIDs: seen ?? Array(Set(rows.map(\.healthKitUUID))),
      deletedSampleIDs: deleted,
      anchor: Data([anchor])
    )
  }

  func measurement(
    _ id: UUID,
    ordinal: Int = 0,
    at seconds: TimeInterval,
    metric: TodayHealthMetric = .heartRate,
    device: String = "watch"
  ) -> HealthMeasurement {
    let date = interval.start.addingTimeInterval(seconds)
    return HealthMeasurement(
      metric: metric,
      healthKitUUID: id,
      ordinal: ordinal,
      startDate: date,
      endDate: date,
      value: 63,
      sourceIdentifier: "beatsense.test",
      deviceIdentifier: device
    )
  }

  func makeBaseline() -> PersonalBaseline {
    PersonalBaseline(
      p10: 35,
      p50: 42,
      p90: 54,
      validDayCount: 25,
      windowStart: interval.start,
      windowEnd: interval.end,
      timeZoneID: "Asia/Tokyo",
      sourceIdentifier: "beatsense.test",
      deviceIdentifier: "watch",
      referencePeriod: 2,
      referenceDuration: 60,
      algorithmVersion: 1,
      computedAt: interval.end
    )
  }
}
