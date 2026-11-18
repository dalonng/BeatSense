@testable import AACUseCases
import AANModels
import Foundation
import Testing

struct HeartRateSummaryAccumulatorTests {
  @Test func `summarizes unordered measurements and counts half-open BPM buckets`() throws {
    let start = Date(timeIntervalSinceReferenceDate: 100)
    let end = start.addingTimeInterval(60)
    let latest = HeartRateSample(beatsPerMinute: 61, date: start.addingTimeInterval(40))
    var accumulator = HeartRateSummaryAccumulator(interval: DateInterval(start: start, end: end))

    accumulator.add(beatsPerMinute: latest.beatsPerMinute, date: latest.date)
    accumulator.add(beatsPerMinute: 52, date: start)
    accumulator.add(beatsPerMinute: 60, date: start.addingTimeInterval(10))
    accumulator.add(beatsPerMinute: 87, date: start.addingTimeInterval(20))

    let result = try #require(accumulator.summary)
    #expect(result.latest == latest)
    #expect(result.averageBPM == 65)
    #expect(result.minimumBPM == 52)
    #expect(result.maximumBPM == 87)
    #expect(result.sampleCount == 4)
    #expect(result.buckets == [
      .init(lowerBoundBPM: 40, upperBoundBPM: 60, count: 1),
      .init(lowerBoundBPM: 60, upperBoundBPM: 80, count: 2),
      .init(lowerBoundBPM: 80, upperBoundBPM: 100, count: 1),
    ])
  }

  @Test func `skips invalid and out-of-window measurements and keeps the top range open`() throws {
    let start = Date(timeIntervalSinceReferenceDate: 100)
    let end = start.addingTimeInterval(1)
    var accumulator = HeartRateSummaryAccumulator(interval: DateInterval(start: start, end: end))

    accumulator.add(beatsPerMinute: .infinity, date: start)
    accumulator.add(beatsPerMinute: 0, date: start)
    accumulator.add(beatsPerMinute: 76, date: start.addingTimeInterval(-1))
    accumulator.add(beatsPerMinute: 76, date: end)
    #expect(accumulator.summary == nil)

    accumulator.add(beatsPerMinute: 260, date: start)
    let result = try #require(accumulator.summary)
    #expect(result.averageBPM == 260)
    #expect(result.buckets == [.init(lowerBoundBPM: 240, upperBoundBPM: nil, count: 1)])
    #expect(result.latest == HeartRateSample(beatsPerMinute: 260, date: start))
  }
}
