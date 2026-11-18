import AAMServices
import AAMStorages
import AANModels
import Foundation
import OSLog

public actor SynchronizeHealthHistory {
  public enum ForegroundChange: Equatable, Sendable {
    case updated
    case authorizationInvalidated
  }

  public static let defaultRetentionDays = 90
  public static let retentionPreferenceKey = "healthHistoryRetentionDays"

  struct Update: Sendable {
    let metric: TodayHealthMetric
    let reading: RefreshTodayHealth.Reading
    var deferredDate: Date?
    var baseline: ReadTodayHealth.Baseline?
  }

  private struct Run {
    let id: UUID
    let task: Task<Void, Never>
    var updates: [Update] = []
    var subscribers: [UUID: AsyncStream<Update>.Continuation] = [:]
  }

  private struct CalendarDay: Equatable {
    let calendarIdentifier: Calendar.Identifier
    let timeZoneIdentifier: String
    let start: Date

    init(now: Date = .now, calendar: Calendar = .current) {
      calendarIdentifier = calendar.identifier
      timeZoneIdentifier = calendar.timeZone.identifier
      start = calendar.startOfDay(for: now)
    }
  }

  private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BeatSense", category: "HealthHistory")

  private let appleHealth: any AppleHealthReading
  private let store: HealthHistoryStore
  private var retentionDays: Int
  private var calendarDay = CalendarDay()
  private var run: Run?
  private var latestUpdates: [Update]?
  private var deferredDates: [TodayHealthMetric: Date] = [:]
  private var foregroundTask: Task<Void, Never>?
  private var calendarRefreshTask: Task<Void, Never>?
  private var foregroundSubscribers: [UUID: AsyncStream<ForegroundChange>.Continuation] = [:]
  private var pendingInvalidation: Task<Void, Never>?
  private var verificationGeneration = UUID()

  public init(
    appleHealth: any AppleHealthReading,
    store: HealthHistoryStore,
    retentionDays: Int = defaultRetentionDays
  ) {
    self.appleHealth = appleHealth
    self.store = store
    self.retentionDays = Self.retentionStart(days: retentionDays, now: .now, calendar: .current) == nil
      ? Self.defaultRetentionDays : retentionDays
  }

  public nonisolated static func isValidRetention(_ days: Int) -> Bool {
    retentionStart(days: days, now: .now, calendar: .current) != nil
  }

  public func setRetentionDays(_ days: Int) async {
    guard days != retentionDays,
          let cutoff = Self.retentionStart(days: days, now: .now, calendar: .current) else { return }
    let shrink = days < retentionDays
    retentionDays = days
    await invalidate(pruningBefore: shrink ? cutoff : nil)
    guard days == retentionDays, !foregroundSubscribers.isEmpty else { return }
    await synchronizeAndNotify()
  }

  public func calendarDidChange() {
    guard !Task.isCancelled, !foregroundSubscribers.isEmpty else { return }
    let day = CalendarDay()
    guard day != calendarDay else { return }
    calendarDay = day
    // The shared sync owns the refresh even if the window that received the event goes inactive.
    calendarRefreshTask?.cancel()
    calendarRefreshTask = Task {
      guard !Task.isCancelled else { return }
      await invalidate()
      await synchronizeAndNotify()
    }
  }

  /// Owns one observation task across all active windows.
  public func observeForeground(
    _ consume: @MainActor @Sendable (AsyncStream<ForegroundChange>) async -> Void
  ) async {
    guard !Task.isCancelled else { return }
    let id = UUID()
    let (changes, continuation) = AsyncStream<ForegroundChange>.makeStream(bufferingPolicy: .bufferingNewest(2))
    foregroundSubscribers[id] = continuation
    if foregroundTask == nil {
      foregroundTask = Task { await observeSource() }
    }
    await consume(changes)
    continuation.finish()
    foregroundSubscribers[id] = nil
    if foregroundSubscribers.isEmpty {
      foregroundTask?.cancel()
      foregroundTask = nil
      calendarRefreshTask?.cancel()
      calendarRefreshTask = nil
      await invalidate()
    }
  }

  func invalidate(pruningBefore cutoff: Date? = nil, notifyingAuthorizationChange: Bool = false) async {
    verificationGeneration = UUID()
    stopRun()
    latestUpdates = nil
    deferredDates.removeAll()
    if notifyingAuthorizationChange {
      notifyForegroundSubscribers(.authorizationInvalidated)
    }
    let priorInvalidation = pendingInvalidation
    let task = Task { [store] in
      await priorInvalidation?.value
      await store.invalidateVerification()
      if let cutoff {
        do {
          try await store.pruneExpired(before: cutoff)
        } catch {
          Self.log(error)
        }
      }
    }
    pendingInvalidation = task
    await task.value
    if pendingInvalidation == task {
      pendingInvalidation = nil
    }
  }

  func invalidateAuthorization() async {
    let hadPublishedReadings = latestUpdates != nil || run?.updates.isEmpty == false
    await invalidate(notifyingAuthorizationChange: hadPublishedReadings)
  }

  func readTrend(
    for metric: TodayHealthMetric,
    using projection: ReadDailyHealthTrend
  ) async throws -> [DailyHealthValue] {
    try await projection(metric, from: store)
  }

  func readTimeline(
    for metric: TodayHealthMetric,
    in interval: DateInterval,
    verification: UUID
  ) async throws -> [IntradayHealthPoint] {
    try Task.checkCancellation()
    guard isCurrentVerification(verification) else { throw HealthHistoryStore.StoreError.unverified }
    let timeline = try await store.reduceReadings(
      for: metric, in: interval, into: IntradayHealthTimeline(interval: interval)
    ) { timeline, sample in
      timeline.add(sample)
    }
    try Task.checkCancellation()
    guard isCurrentVerification(verification) else { throw HealthHistoryStore.StoreError.unverified }
    return timeline.points
  }

  func verifiedUpdates(reusingLatest: Bool = false) async -> (generation: UUID, updates: AsyncStream<Update>) {
    while let pendingInvalidation {
      await pendingInvalidation.value
      if self.pendingInvalidation == pendingInvalidation {
        self.pendingInvalidation = nil
      }
    }
    let (stream, continuation) = AsyncStream<Update>.makeStream()
    guard !Task.isCancelled else {
      continuation.finish()
      return (verificationGeneration, stream)
    }
    if run == nil, reusingLatest, let latestUpdates {
      for update in latestUpdates {
        continuation.yield(update)
      }
      continuation.finish()
      return (verificationGeneration, stream)
    }
    let subscriber = UUID()
    continuation.onTermination = { [weak self] _ in
      Task { await self?.removeSubscriber(subscriber) }
    }
    if run == nil {
      let id = UUID()
      run = Run(id: id, task: Task { await synchronize(id: id) })
    }
    for update in run?.updates ?? [] {
      continuation.yield(update)
    }
    run?.subscribers[subscriber] = continuation
    return (verificationGeneration, stream)
  }

  func isCurrentVerification(_ generation: UUID) -> Bool {
    generation == verificationGeneration
  }

  func verifiedRetentionDays(for generation: UUID) -> Int? {
    isCurrentVerification(generation) ? retentionDays : nil
  }

  func notifyVerifiedUpdate(_ generation: UUID) {
    guard isCurrentVerification(generation) else { return }
    notifyForegroundSubscribers(.updated)
  }

  private func removeSubscriber(_ id: UUID) {
    run?.subscribers[id] = nil
  }

  private func stopRun() {
    guard let run else { return }
    self.run = nil
    run.task.cancel()
    for subscriber in run.subscribers.values {
      subscriber.finish()
    }
  }

  private func notifyForegroundSubscribers(_ change: ForegroundChange) {
    for subscriber in foregroundSubscribers.values {
      subscriber.yield(change)
    }
  }

  private func synchronize(id: UUID) async {
    do {
      try await loadUpdates(for: id)
    } catch {
      guard run?.id == id, !Task.isCancelled else { return }
      await store.invalidateVerification()
      guard run?.id == id, !Task.isCancelled else { return }
      Self.log(error)
      for metric in TodayHealthMetric.allCases {
        publish(Update(metric: metric, reading: .failed))
      }
    }
    guard let run, run.id == id, !Task.isCancelled else { return }
    latestUpdates = run.updates
    self.run = nil
    for subscriber in run.subscribers.values {
      subscriber.finish()
    }
    await retireLegacySnapshot(after: run.updates)
  }

  private func publish(_ update: Update) {
    deferredDates[update.metric] = update.deferredDate
    run?.updates.append(update)
    for subscriber in run?.subscribers.values ?? [:].values {
      subscriber.yield(update)
    }
  }

  static func retentionStart(days: Int, now: Date, calendar: Calendar) -> Date? {
    guard days > 0, let start = calendar.date(byAdding: .day, value: -days, to: now),
          start < now, start.timeIntervalSinceReferenceDate.isFinite else { return nil }
    return start
  }

  private static func log(_ error: any Error, metric: TodayHealthMetric? = nil) {
    let code = (error as NSError).code
    let scope = metric?.rawValue ?? "all metrics"
    logger.error("Health history sync failed for \(scope, privacy: .public), code \(code, privacy: .public).")
  }
}

private extension SynchronizeHealthHistory {
  func observeSource() async {
    do {
      try await appleHealth.observeSampleChanges { changes in
        await self.synchronizeAndNotify()
        for await _ in changes {
          do {
            try await Task.sleep(for: .milliseconds(400))
          } catch {
            return
          }
          await self.synchronizeAndNotify()
        }
      }
    } catch is CancellationError {
      return
    } catch {
      Self.log(error)
      await synchronizeAndNotify()
    }
  }

  func synchronizeAndNotify() async {
    do {
      try Task.checkCancellation()
      if try await appleHealth.needsAuthorizationRequest(for: .measurements) {
        try Task.checkCancellation()
        await invalidateAuthorization()
        return
      }
      let (generation, stream) = await verifiedUpdates()
      for await _ in stream {}
      guard !Task.isCancelled else { return }
      notifyVerifiedUpdate(generation)
    } catch is CancellationError {
      return
    } catch {
      Self.log(error)
      await invalidateAuthorization()
    }
  }
}

private extension SynchronizeHealthHistory {
  func loadUpdates(for id: UUID) async throws {
    try Task.checkCancellation()
    let now = Date.now
    let calendar = Calendar.current
    calendarDay = CalendarDay(now: now, calendar: calendar)
    guard let cutoff = Self.retentionStart(days: retentionDays, now: now, calendar: calendar),
          let readToday = ReadTodayHealth(now: now, calendar: calendar)
    else {
      throw AppleHealthError.queryFailed
    }
    let synchronizeMetric = SynchronizeHealthMetric(
      source: appleHealth, store: store, interval: DateInterval(start: cutoff, end: now)
    )
    // Expiry depends on local time and storage availability, even if a HealthKit query fails later.
    try await store.pruneExpired(before: cutoff)
    let authorizationDates = try await appleHealth.earliestAuthorizedSampleDates()
    await withTaskGroup(of: Update.self) { group in
      for metric in TodayHealthMetric.allCases {
        let authorizationStart = authorizationDates[metric]
        let deferredDate = deferredDates[metric]
        group.addTask { [store] in
          do {
            let nextDeferred = try await synchronizeMetric(
              metric,
              authorizationStart: authorizationStart,
              deferredDate: deferredDate
            )
            let today = try await readToday(metric, from: store)
            return Update(metric: metric, reading: today.reading, deferredDate: nextDeferred, baseline: today.baseline)
          } catch {
            if !Task.isCancelled {
              await store.invalidateVerification(for: metric)
              Self.log(error, metric: metric)
            }
            return Update(metric: metric, reading: .failed)
          }
        }
      }
      for await update in group {
        guard run?.id == id, !Task.isCancelled else {
          group.cancelAll()
          return
        }
        publish(update)
      }
    }
  }

  func retireLegacySnapshot(after updates: [Update]) async {
    for update in updates {
      if case .failed = update.reading {
        return
      }
    }
    do {
      try await store.removeLegacySnapshot()
    } catch {
      Self.log(error)
    }
  }
}
