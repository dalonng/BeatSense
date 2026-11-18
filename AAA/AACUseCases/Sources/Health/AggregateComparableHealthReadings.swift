import AANModels
import Foundation

struct ComparableHealthReference {
  let sourceIdentifier: String
  let deviceIdentifier: String?
  var period: Int?
  let duration: TimeInterval?
}

/// Selects compatible samples for Today's personal baselines and daily trend values.
struct AggregateComparableHealthReadings<Sample: Sendable> {
  enum Method {
    case latest
    case medianInComparablePeriod
  }

  let value: KeyPath<Sample, Double>
  let date: KeyPath<Sample, Date>
  let method: Method
  let calendar: Calendar

  func isUsable(_ reading: SourcedHealthSample<Sample>) -> Bool {
    let measurement = reading.sample[keyPath: value]
    guard measurement.isFinite else { return false }
    switch method {
    case .latest:
      return measurement > 0
    case .medianInComparablePeriod:
      return measurement >= 0 && reading.duration.isFinite && reading.duration >= 0
    }
  }

  func latest(in readings: [SourcedHealthSample<Sample>]) -> SourcedHealthSample<Sample>? {
    readings.max { $0.sample[keyPath: date] < $1.sample[keyPath: date] }
  }

  func reference(for reading: SourcedHealthSample<Sample>) -> ComparableHealthReference {
    ComparableHealthReference(
      sourceIdentifier: reading.sourceIdentifier,
      deviceIdentifier: reading.deviceIdentifier,
      period: method == .medianInComparablePeriod ? period(for: reading) : nil,
      duration: method == .medianInComparablePeriod ? reading.duration : nil
    )
  }

  func isComparable(_ reading: SourcedHealthSample<Sample>, to reference: ComparableHealthReference) -> Bool {
    matchesRecording(reading, to: reference) && (method == .latest || period(for: reading) == reference.period)
  }

  func matchesRecording(_ reading: SourcedHealthSample<Sample>, to reference: ComparableHealthReference) -> Bool {
    guard reading.sourceIdentifier == reference.sourceIdentifier,
          reading.deviceIdentifier == reference.deviceIdentifier else { return false }
    switch method {
    case .latest:
      return true
    case .medianInComparablePeriod:
      guard let duration = reference.duration else { return false }
      // Missing duration metadata is only comparable to other missing durations.
      if duration == 0 || reading.duration == 0 {
        return reading.duration == duration
      }
      return abs(reading.duration - duration) <= 15
    }
  }

  func dailyValue(in readings: [SourcedHealthSample<Sample>]) -> Double? {
    switch method {
    case .latest:
      latest(in: readings)?.sample[keyPath: value]
    case .medianInComparablePeriod:
      healthPercentile(0.5, of: readings.map { $0.sample[keyPath: value] }.sorted())
    }
  }

  func period(for reading: SourcedHealthSample<Sample>) -> Int {
    calendar.component(.hour, from: reading.sample[keyPath: date]) / 2
  }
}

func healthPercentile(_ fraction: Double, of sorted: [Double]) -> Double? {
  guard !sorted.isEmpty else { return nil }
  let rank = fraction * Double(sorted.count - 1)
  let index = Int(rank)
  let next = sorted[min(index + 1, sorted.count - 1)]
  return sorted[index] + (next - sorted[index]) * (rank - Double(index))
}

extension HealthMeasurement {
  func sourced<Sample: Sendable>(_ sample: Sample) -> SourcedHealthSample<Sample> {
    SourcedHealthSample(
      sample: sample,
      sourceIdentifier: sourceIdentifier,
      deviceIdentifier: deviceIdentifier,
      duration: endDate.timeIntervalSince(startDate)
    )
  }
}
