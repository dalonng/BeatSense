import AANModels
import Foundation
import SwiftData

public actor HealthHistoryStore {
  public struct Reconciliation: Sendable {
    public let generation: UUID
    public let reusableSampleIDs: Set<UUID>
  }

  public struct Checkpoint: Sendable {
    public let generation: UUID
    public let anchor: Data?
    public let queryStart: Date
    public let isVerified: Bool
  }

  public struct BaselineInput: Sendable {
    public let generation: UUID
    public let revision: UUID
    public let measurements: [HealthMeasurement]
    public let baseline: PersonalBaseline?
    /// Selection context from an invalidated HRV baseline. Its statistics have been cleared.
    public let previousHRVReference: PersonalBaseline?
  }

  public enum StoreError: Error, Equatable {
    case unverified
    case superseded
    case invalidBatch
    case incompleteReconciliation
  }

  private let inMemory: Bool
  private let directory: URL
  private let legacyDirectory: URL?
  private var database: HealthHistoryDatabase?

  public init(inMemory: Bool = false) {
    let support = URL.applicationSupportDirectory
    self.init(
      inMemory: inMemory,
      directory: support.appending(path: "HealthHistory", directoryHint: .isDirectory),
      legacyDirectory: support.appending(path: "TodayHealth", directoryHint: .isDirectory)
    )
  }

  init(inMemory: Bool = false, directory: URL, legacyDirectory: URL? = nil) {
    self.inMemory = inMemory
    self.directory = directory
    self.legacyDirectory = legacyDirectory
  }

  public func beginReconciliation(
    for metric: TodayHealthMetric,
    retainingFrom cutoff: Date,
    queryStart: Date
  ) async throws -> Reconciliation {
    try await open().beginReconciliation(for: metric, retainingFrom: cutoff, queryStart: queryStart)
  }

  public func apply(
    _ batch: HealthSampleBatch,
    for metric: TodayHealthMetric,
    generation: UUID,
    expectedAnchor: Data?,
    retainingIn interval: DateInterval
  ) async throws {
    try await open().apply(
      batch,
      for: metric,
      generation: generation,
      expectedAnchor: expectedAnchor,
      retainingIn: interval
    )
  }

  public func finishReconciliation(
    for metric: TodayHealthMetric,
    generation: UUID,
    retainingIn interval: DateInterval
  ) async throws {
    try await open().finishReconciliation(for: metric, generation: generation, retainingIn: interval)
  }

  public func checkpoint(for metric: TodayHealthMetric) async throws -> Checkpoint? {
    try await open().checkpoint(for: metric)
  }

  public func prune(for metric: TodayHealthMetric, retainingIn interval: DateInterval, generation: UUID) async throws {
    try await open().prune(for: metric, retainingIn: interval, generation: generation)
  }

  /// Enforces the retention policy independently of HealthKit access.
  public func pruneExpired(before cutoff: Date) async throws {
    try await open().pruneExpired(before: cutoff)
  }

  public func readings(
    for metric: TodayHealthMetric,
    in interval: DateInterval,
    limit: Int? = nil,
    offset: Int = 0
  ) async throws -> [HealthMeasurement] {
    try await open().readings(for: metric, in: interval, limit: limit, offset: offset)
  }

  /// Reads one verified snapshot in bounded batches on the database actor.
  public func reduceReadings<Result: Sendable>(
    for metric: TodayHealthMetric,
    in interval: DateInterval,
    into initial: Result,
    _ accumulate: @Sendable (inout Result, HealthMeasurement) throws -> Void
  ) async throws -> Result {
    try await open().reduceReadings(for: metric, in: interval, into: initial, accumulate)
  }

  public func baselineInput(for metric: TodayHealthMetric, in interval: DateInterval) async throws -> BaselineInput {
    try await open().baselineInput(for: metric, in: interval)
  }

  public func personalBaseline(
    for metric: TodayHealthMetric,
    window: DateInterval,
    timeZoneID: String,
    algorithmVersion: Int
  ) async throws -> PersonalBaseline? {
    try await open().personalBaseline(
      for: metric,
      window: window,
      timeZoneID: timeZoneID,
      algorithmVersion: algorithmVersion
    )
  }

  public func saveBaseline(
    _ baseline: PersonalBaseline,
    for metric: TodayHealthMetric,
    expectedGeneration: UUID,
    expectedRevision: UUID
  ) async throws -> Bool {
    try await open().saveBaseline(
      baseline,
      for: metric,
      expectedGeneration: expectedGeneration,
      expectedRevision: expectedRevision
    )
  }

  /// Closes the visibility gate and invalidates outstanding writes without opening the store.
  public func invalidateVerification(for metric: TodayHealthMetric? = nil) async {
    await database?.invalidateVerification(for: metric)
  }

  /// Retires the previous rebuildable Today snapshot after the new history has been verified.
  public func removeLegacySnapshot() throws {
    try Task.checkCancellation()
    guard !inMemory, let legacyDirectory else { return }
    do {
      try FileManager.default.removeItem(at: legacyDirectory)
    } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
      return
    }
  }

  private func open() throws -> HealthHistoryDatabase {
    try Task.checkCancellation()
    if let database {
      return database
    }

    let schema = Schema(versionedSchema: HealthHistorySchemaV1.self)
    let configuration: ModelConfiguration
    if inMemory {
      configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    } else {
      var directory = directory
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.complete]
      )
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try directory.setResourceValues(values)
      configuration = ModelConfiguration(
        schema: schema,
        url: directory.appending(path: "HealthSamples.store"),
        cloudKitDatabase: .none
      )
    }

    let container = try ModelContainer(for: schema, configurations: configuration)
    // Open the private model context off the main actor.
    let database = HealthHistoryDatabase(modelContainer: container)
    self.database = database
    return database
  }
}
