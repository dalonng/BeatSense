import AANModels
import Foundation
import HealthKit
import OSLog

public actor AppleHealthClient: AppleHealthReading {
  private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BeatSense", category: "AppleHealth")

  private var store: HKHealthStore?
  private var authorizationRequest: (types: Set<HKObjectType>, task: Task<Void, any Error>)?

  public init() {}

  public func needsAuthorizationRequest(for scope: AppleHealthReadScope) async throws -> Bool {
    try Task.checkCancellation()
    let store = try availableStore()
    let status: HKAuthorizationRequestStatus
    do {
      status = try await store.statusForAuthorizationRequest(toShare: [], read: scope.readTypes)
    } catch {
      throw Self.serviceError(for: error, fallback: .authorizationFailed)
    }
    try Task.checkCancellation()

    switch status {
    case .shouldRequest:
      return true
    case .unnecessary:
      return false
    default:
      Self.logger.error("Could not determine the Apple Health authorization request status.")
      throw AppleHealthError.authorizationFailed
    }
  }

  public func requestReadAuthorization(for scope: AppleHealthReadScope) async throws {
    try Task.checkCancellation()
    let store = try availableStore()
    let types = scope.readTypes

    do {
      while let active = authorizationRequest {
        if active.types.isSuperset(of: types) {
          try await active.task.value
          try Task.checkCancellation()
          return
        }
        // Another window owns this sheet. Its outcome doesn't decide the remaining types.
        _ = await active.task.result
        guard try await needsAuthorizationRequest(for: scope) else { return }
      }
      // The system sheet can outlive the view or window that requested it.
      let request = Task {
        defer { authorizationRequest = nil }
        try await store.requestAuthorization(toShare: [], read: types)
      }
      authorizationRequest = (types, request)
      try await request.value
    } catch let error as AppleHealthError {
      throw error
    } catch {
      throw Self.serviceError(for: error, fallback: .authorizationFailed)
    }
    try Task.checkCancellation()
  }

  public func observeSampleChanges(_ consume: @Sendable (AsyncStream<Void>) async -> Void) async throws {
    try Task.checkCancellation()
    let store = try availableStore()
    let (changes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let queries = AppleHealthReadScope.all.readTypes.compactMap { $0 as? HKSampleType }.map { type in
      HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
        defer { completion() }
        if let error {
          let code = (error as NSError).code
          Self.logger.error("Apple Health observer failed, code \(code, privacy: .public).")
          return
        }
        continuation.yield()
      }
    }

    queries.forEach(store.execute)
    defer {
      continuation.finish()
      queries.forEach(store.stop)
    }
    await consume(changes)
  }

  func availableStore() throws -> HKHealthStore {
    guard HKHealthStore.isHealthDataAvailable() else { throw AppleHealthError.unavailable }
    if let store {
      return store
    }

    let store = HKHealthStore()
    self.store = store
    return store
  }

  static func serviceError(for error: any Error, fallback: AppleHealthError) -> any Error {
    if Task.isCancelled || error is CancellationError {
      return CancellationError()
    }

    switch (error as? HKError)?.code {
    case .errorHealthDataUnavailable:
      return AppleHealthError.unavailable
    case .errorHealthDataRestricted:
      return AppleHealthError.restricted
    case .errorUserCanceled:
      return CancellationError()
    default:
      let code = (error as NSError).code
      logger.error("Apple Health \(String(describing: fallback), privacy: .public), code \(code, privacy: .public).")
      return fallback
    }
  }
}

extension AppleHealthReadScope {
  var readTypes: Set<HKObjectType> {
    switch self {
    case .measurements: Set(TodayHealthMetric.allCases.map(\.quantityType))
    case .sleep: [HKCategoryType(.sleepAnalysis)]
    case .all: Self.measurements.readTypes.union(Self.sleep.readTypes)
    }
  }
}
