import AANModels
import Foundation

/// Keeps sparse intervals intact. Dense intervals retain measured extrema per time bucket and the latest reading.
struct IntradayHealthTimeline: Sendable {
  private struct Extrema: Sendable {
    var minimum: IntradayHealthPoint
    var maximum: IntradayHealthPoint

    mutating func include(_ point: IntradayHealthPoint) {
      if point.value < minimum.value || (point.value == minimum.value && point.date < minimum.date) {
        minimum = point
      }
      if point.value > maximum.value || (point.value == maximum.value && point.date > maximum.date) {
        maximum = point
      }
    }
  }

  private static let bucketCount = 96
  private let interval: DateInterval
  private let bucketDuration: TimeInterval
  private var sparsePoints: [IntradayHealthPoint]? = []
  private var extrema: [Int: Extrema] = [:]
  private var latest: IntradayHealthPoint?

  init(interval: DateInterval) {
    self.interval = interval
    bucketDuration = max(1, interval.duration / Double(Self.bucketCount))
  }

  mutating func add(_ sample: HealthMeasurement) {
    guard sample.endDate >= interval.start, sample.endDate < interval.end, sample.value.isFinite else { return }
    switch sample.metric {
    case .heartRate, .restingHeartRate:
      guard sample.value > 0 else { return }
    case .heartRateVariability:
      guard sample.value >= 0 else { return }
    case .bloodOxygen, .respiratoryRate:
      break
    }

    let point = IntradayHealthPoint(date: sample.endDate, value: sample.value)
    if sparsePoints?.count == 2 * Self.bucketCount + 1 {
      sparsePoints = nil
    }
    sparsePoints?.append(point)
    if latest.map({ point.date > $0.date }) ?? true {
      latest = point
    }
    let position = point.date.timeIntervalSince(interval.start) / bucketDuration
    let index = min(Int(position), Self.bucketCount - 1)
    extrema[index, default: Extrema(minimum: point, maximum: point)].include(point)
  }

  var points: [IntradayHealthPoint] {
    var points = sparsePoints ?? extrema.values.flatMap { bucket in
      bucket.minimum == bucket.maximum ? [bucket.minimum] : [bucket.minimum, bucket.maximum]
    }
    if sparsePoints == nil, let latest, !points.contains(latest) {
      points.append(latest)
    }
    return points.sorted { $0.date == $1.date ? $0.value < $1.value : $0.date < $1.date }
  }
}
