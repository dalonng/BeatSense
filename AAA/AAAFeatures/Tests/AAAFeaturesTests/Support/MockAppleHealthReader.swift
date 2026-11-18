import AAMServices
import AANModels
import Foundation

actor MockAppleHealthReader: AppleHealthReading {
  private var requiresAuthorization: Bool
  private var requiresSleepAuthorization: Bool
  private let failedMetric: TodayHealthMetric?
  private var snapshots: [[HealthMeasurement]]
  private var earliestAuthorizedDates: [TodayHealthMetric: Date] = [:]
  private var suspendHeartRate = false
  private var suspendSleep = false
  private var suspendedQuery: CheckedContinuation<Void, Never>?
  private var queryStarted: CheckedContinuation<Void, Never>?

  private(set) var requestedScopes: [AppleHealthReadScope] = []
  var authorizationRequests: Int {
    requestedScopes.count
  }

  private(set) var queryStarts: [Date] = []
  private(set) var sleepQueries: [DateInterval] = []
  private var sleepSamples: [SleepSample] = []
  private var sleepError: AppleHealthError?

  init(
    samples: [HealthMeasurement] = [],
    needsAuthorizationRequest: Bool = false,
    needsSleepAuthorization: Bool = false,
    failedMetric: TodayHealthMetric? = nil
  ) {
    requiresAuthorization = needsAuthorizationRequest
    requiresSleepAuthorization = needsAuthorizationRequest || needsSleepAuthorization
    self.failedMetric = failedMetric
    snapshots = [samples]
  }

  func needsAuthorizationRequest(for scope: AppleHealthReadScope) async throws -> Bool {
    switch scope {
    case .measurements: requiresAuthorization
    case .sleep: requiresSleepAuthorization
    case .all: requiresAuthorization || requiresSleepAuthorization
    }
  }

  func requestReadAuthorization(for scope: AppleHealthReadScope) async throws {
    requestedScopes.append(scope)
    if scope != .sleep {
      requiresAuthorization = false
    }
    if scope != .measurements {
      requiresSleepAuthorization = false
    }
  }

  func observeSampleChanges(_ consume: @Sendable (AsyncStream<Void>) async -> Void) async throws {
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    continuation.finish()
    await consume(stream)
  }

  func earliestAuthorizedSampleDates() async throws -> [TodayHealthMetric: Date] {
    earliestAuthorizedDates
  }

  func sleepSamples(in interval: DateInterval) async throws -> [SleepSample] {
    sleepQueries.append(interval)
    if suspendSleep {
      suspendSleep = false
      await suspendQuery()
    }
    if let sleepError {
      throw sleepError
    }
    return sleepSamples
  }

  func setSleepSamples(_ samples: [SleepSample]) {
    sleepSamples = samples
    sleepError = nil
  }

  func failSleepQuery() {
    sleepError = .queryFailed
  }

  func sampleChanges(
    for metric: TodayHealthMetric,
    since start: Date,
    anchor: Data?,
    reusing sampleIDs: Set<UUID>
  ) async throws -> HealthSampleBatch {
    queryStarts.append(start)
    if failedMetric == metric {
      throw AppleHealthError.queryFailed
    }
    let index = snapshots.count - 1
    let current = snapshots[index].filter { $0.metric == metric && $0.endDate >= start }
    let old = anchor?.first.map { snapshots[Int($0)] } ?? []
    let oldIDs = Set(old.lazy.filter { $0.metric == metric && $0.endDate >= start }.map(\.healthKitUUID))
    let currentIDs = Set(current.map(\.healthKitUUID))
    let added = current.filter { !oldIDs.contains($0.healthKitUUID) }
    if metric == .heartRate, suspendHeartRate {
      suspendHeartRate = false
      await suspendQuery()
    }
    return HealthSampleBatch(
      measurements: added.filter { !sampleIDs.contains($0.healthKitUUID) },
      seenSampleIDs: added.map(\.healthKitUUID),
      deletedSampleIDs: Array(oldIDs.subtracting(currentIDs)),
      anchor: Data([UInt8(index)])
    )
  }

  func replaceSamples(for metric: TodayHealthMetric, with samples: [HealthMeasurement]) {
    var current = snapshots[snapshots.count - 1]
    current.removeAll { $0.metric == metric }
    current += samples
    snapshots.append(current)
  }

  func requireAuthorization() {
    requiresAuthorization = true
  }

  func limitHistory(for metric: TodayHealthMetric, since date: Date) {
    earliestAuthorizedDates[metric] = date
  }

  func suspendNextHeartRateQuery() {
    suspendHeartRate = true
  }

  func suspendNextSleepQuery() {
    suspendSleep = true
  }

  private func suspendQuery() async {
    await withCheckedContinuation { continuation in
      suspendedQuery = continuation
      queryStarted?.resume()
      queryStarted = nil
    }
  }

  func waitForSuspendedQuery() async {
    if suspendedQuery != nil {
      return
    }
    await withCheckedContinuation { continuation in
      queryStarted = continuation
    }
  }

  func resumeSuspendedQuery() {
    suspendedQuery?.resume()
    suspendedQuery = nil
  }
}
