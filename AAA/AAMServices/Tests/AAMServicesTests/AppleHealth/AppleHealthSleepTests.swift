@testable import AAMServices
import AANModels
import Foundation
import HealthKit
import Testing

struct AppleHealthSleepTests {
  private let window = DateInterval(start: Date(timeIntervalSinceReferenceDate: 100), duration: 100)

  @Test(arguments: [
    (HKCategoryValueSleepAnalysis.asleepUnspecified, SleepSample.State.asleep),
    (.asleepCore, .core),
    (.asleepDeep, .deep),
    (.asleepREM, .rem),
  ])
  func `asleep samples retain their stage and endpoints across the window boundary`(
    value: HKCategoryValueSleepAnalysis, state: SleepSample.State
  ) {
    let sample = makeSample(value, start: 80, duration: 30)
    let normalized = AppleHealthClient.sleepSample(sample, overlapping: window)
    #expect(normalized == SleepSample(
      interval: DateInterval(start: sample.startDate, end: sample.endDate),
      state: state
    ))
  }

  @Test func `awake intervals are preserved and in-bed periods are ignored`() {
    let awake = makeSample(.awake, start: 110, duration: 5)
    #expect(AppleHealthClient.sleepSample(awake, overlapping: window)?.state == .awake)
    let inBed = makeSample(.inBed, start: 90, duration: 150)
    #expect(AppleHealthClient.sleepSample(inBed, overlapping: window) == nil)
  }

  @Test func `samples touching a boundary have no positive overlap`() {
    let before = makeSample(.asleepDeep, start: 90, duration: 10)
    let after = makeSample(.asleepDeep, start: 200, duration: 10)
    #expect(AppleHealthClient.sleepSample(before, overlapping: window) == nil)
    #expect(AppleHealthClient.sleepSample(after, overlapping: window) == nil)
  }

  @Test func `empty windows are rejected before querying the store`() async {
    let empty = DateInterval(start: window.start, duration: 0)
    await #expect(throws: AppleHealthError.queryFailed) {
      try await AppleHealthClient().sleepSamples(in: empty)
    }
  }

  private func makeSample(
    _ value: HKCategoryValueSleepAnalysis,
    start: TimeInterval,
    duration: TimeInterval
  ) -> HKCategorySample {
    let date = Date(timeIntervalSinceReferenceDate: start)
    return HKCategorySample(
      type: HKCategoryType(.sleepAnalysis), value: value.rawValue, start: date, end: date.addingTimeInterval(duration)
    )
  }
}
