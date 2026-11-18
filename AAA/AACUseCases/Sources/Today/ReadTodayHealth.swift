import AAMStorages
import AANModels
import Foundation

struct ReadTodayHealth: Sendable {
  struct Baseline: Sendable {
    let range: HealthBaselineRange
    let day: Date
    let timeZoneID: String
  }

  struct Result: Sendable {
    let reading: RefreshTodayHealth.Reading
    var baseline: Baseline?
  }

  private let recentInterval: DateInterval
  private let calculateBaseline: CalculateTodayPersonalBaseline

  init?(now: Date, calendar: Calendar) {
    guard let recentStart = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
    let interval = DateInterval(start: recentStart, end: now)
    guard let calculateBaseline = CalculateTodayPersonalBaseline(recentInterval: interval, calendar: calendar)
    else { return nil }
    recentInterval = interval
    self.calculateBaseline = calculateBaseline
  }

  func callAsFunction(_ metric: TodayHealthMetric, from store: HealthHistoryStore) async throws -> Result {
    switch metric {
    case .heartRate:
      return try await Result(reading: heartRate(from: store))
    case .bloodOxygen:
      guard let sample = try await store.readings(for: metric, in: recentInterval, limit: 1).first
      else { return Result(reading: .empty) }
      return Result(reading: .bloodOxygen(.init(saturation: sample.value, date: sample.endDate)))
    case .respiratoryRate:
      guard let sample = try await store.readings(for: metric, in: recentInterval, limit: 1).first
      else { return Result(reading: .empty) }
      return Result(reading: .respiratoryRate(.init(breathsPerMinute: sample.value, date: sample.endDate)))
    case .restingHeartRate, .heartRateVariability:
      return try await readBaseline(for: metric, from: store)
    }
  }

  private func heartRate(from store: HealthHistoryStore) async throws -> RefreshTodayHealth.Reading {
    let accumulator = try await store.reduceReadings(
      for: .heartRate,
      in: recentInterval,
      into: HeartRateSummaryAccumulator(interval: recentInterval)
    ) { accumulator, sample in
      accumulator.add(beatsPerMinute: sample.value, date: sample.endDate)
    }
    return accumulator.summary.map(RefreshTodayHealth.Reading.heartRate) ?? .empty
  }

  private func readBaseline(
    for metric: TodayHealthMetric,
    from store: HealthHistoryStore
  ) async throws -> Result {
    let input = try await store.baselineInput(for: metric, in: calculateBaseline.queryInterval)
    let baseline: PersonalBaseline
    let reading: RefreshTodayHealth.Reading
    if metric == .restingHeartRate {
      let samples = input.measurements.map { $0.sourced(RestingHeartRateSample(
        beatsPerMinute: $0.value,
        date: $0.endDate
      )) }
      let result = calculateBaseline.restingHeartRate(samples, reusing: input.baseline)
      baseline = result.baseline
      reading = .restingHeartRate(result.latest, assessment: result.assessment)
    } else {
      let samples = input.measurements.map { $0.sourced(HeartRateVariabilitySample(
        sdnnMilliseconds: $0.value,
        date: $0.endDate
      )) }
      let result = calculateBaseline.heartRateVariability(
        samples, reusing: input.baseline, preferring: input.previousHRVReference
      )
      baseline = result.baseline
      reading = .heartRateVariability(result.latest, assessment: result.assessment)
    }
    if baseline != input.baseline {
      try Task.checkCancellation()
      guard try await store.saveBaseline(
        baseline, for: metric, expectedGeneration: input.generation, expectedRevision: input.revision
      ) else {
        throw CancellationError()
      }
    }
    let publishedBaseline = CalculateTodayPersonalBaseline.range(for: baseline).map {
      Baseline(range: $0, day: baseline.windowEnd, timeZoneID: baseline.timeZoneID)
    }
    return Result(reading: reading, baseline: publishedBaseline)
  }
}
