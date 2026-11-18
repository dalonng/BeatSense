import AANModels
import Foundation
import HealthKit

extension AppleHealthClient {
  public func sleepSamples(in interval: DateInterval) async throws -> [SleepSample] {
    try Task.checkCancellation()
    guard interval.start.timeIntervalSinceReferenceDate.isFinite, interval.duration.isFinite,
          interval.duration > 0, interval.end.timeIntervalSinceReferenceDate.isFinite
    else { throw AppleHealthError.queryFailed }
    let store = try availableStore()
    let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
    let query = HKSampleQueryDescriptor(
      predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
      sortDescriptors: []
    )
    do {
      let samples = try await query.result(for: store)
      try Task.checkCancellation()
      return try samples.compactMap { sample in
        try Task.checkCancellation()
        return Self.sleepSample(sample, overlapping: interval)
      }
    } catch let error as HKError where error.code == .errorNoData {
      try Task.checkCancellation()
      return []
    } catch {
      throw Self.serviceError(for: error, fallback: .queryFailed)
    }
  }

  static func sleepSample(_ sample: HKCategorySample, overlapping interval: DateInterval) -> SleepSample? {
    let start = sample.startDate
    let end = sample.endDate
    guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value),
          start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite,
          start < end, start < interval.end, end > interval.start else { return nil }
    let state: SleepSample.State
    switch value {
    case .asleepCore: state = .core
    case .asleepDeep: state = .deep
    case .asleepREM: state = .rem
    case .asleepUnspecified: state = .asleep
    case .awake: state = .awake
    case .inBed: return nil
    @unknown default:
      guard HKCategoryValueSleepAnalysis.allAsleepValues.contains(value) else { return nil }
      state = .asleep
    }
    return SleepSample(interval: DateInterval(start: start, end: end), state: state)
  }
}
