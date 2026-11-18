import AANModels
import Foundation

struct HeartRateSummaryAccumulator {
  private static let bucketWidthBPM = 20
  private static let lastBucketStartBPM = 240

  private let interval: DateInterval
  private var latest: HeartRateSample?
  private var count = 0
  private var averageBPM = 0.0
  private var minimumBPM = Double.infinity
  private var maximumBPM = 0.0
  private var bucketCounts: [Int: Int] = [:]

  init(interval: DateInterval) {
    self.interval = interval
  }

  mutating func add(beatsPerMinute: Double, date: Date) {
    guard date >= interval.start, date < interval.end, beatsPerMinute.isFinite, beatsPerMinute > 0 else { return }
    let sample = HeartRateSample(beatsPerMinute: beatsPerMinute, date: date)
    if latest.map({ date > $0.date }) ?? true {
      latest = sample
    }
    count += 1
    averageBPM += (beatsPerMinute - averageBPM) / Double(count)
    minimumBPM = min(minimumBPM, beatsPerMinute)
    maximumBPM = max(maximumBPM, beatsPerMinute)

    let boundedBPM = min(beatsPerMinute, Double(Self.lastBucketStartBPM))
    let bucketStart = Int(boundedBPM) / Self.bucketWidthBPM * Self.bucketWidthBPM
    bucketCounts[bucketStart, default: 0] += 1
  }

  var summary: HeartRateSummary? {
    guard let latest else { return nil }
    let buckets = bucketCounts.sorted { $0.key < $1.key }.map { start, count in
      HeartRateSummary.Bucket(
        lowerBoundBPM: start,
        upperBoundBPM: start == Self.lastBucketStartBPM ? nil : start + Self.bucketWidthBPM,
        count: count
      )
    }
    return HeartRateSummary(
      latest: latest,
      averageBPM: averageBPM,
      minimumBPM: minimumBPM,
      maximumBPM: maximumBPM,
      buckets: buckets
    )
  }
}
