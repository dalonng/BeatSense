import AANModels
import Foundation

public struct TodayBaselineAssessment: Equatable, Sendable {
  public enum Position: Equatable, Sendable {
    case belowRange
    case withinRange
    case aboveRange
  }

  public enum Status: Equatable, Sendable {
    case building
    case noCurrentReading
    case compared(difference: Double, position: Position)
  }

  public let todayValue: Double?
  public let status: Status
}

struct CalculateTodayPersonalBaseline: Sendable {
  struct Reading<Sample: Sendable>: Sendable {
    let latest: Sample?
    let assessment: TodayBaselineAssessment
    let baseline: PersonalBaseline
  }

  private static let hrvAlgorithmVersion = 3
  private static let minimumValidDays = 21

  let queryInterval: DateInterval
  private let calendar: Calendar
  private let todayStart: Date
  private let recentStart: Date

  init?(recentInterval: DateInterval, calendar: Calendar) {
    let todayStart = calendar.startOfDay(for: recentInterval.end)
    guard let historyStart = calendar.date(byAdding: .day, value: -28, to: todayStart) else { return nil }
    queryInterval = DateInterval(start: historyStart, end: recentInterval.end)
    self.calendar = calendar
    self.todayStart = todayStart
    recentStart = recentInterval.start
  }

  /// Pass a stored baseline only when the input revision still matches.
  func restingHeartRate(
    _ samples: [SourcedHealthSample<RestingHeartRateSample>],
    reusing baseline: PersonalBaseline? = nil
  ) -> Reading<RestingHeartRateSample> {
    assess(
      samples,
      using: .init(value: \.beatsPerMinute, date: \.date, method: .latest, calendar: calendar),
      reusing: baseline,
      algorithmVersion: 2
    )
  }

  /// Only a matching input revision can supply percentiles. A previous revision can propose its HRV period.
  func heartRateVariability(
    _ samples: [SourcedHealthSample<HeartRateVariabilitySample>],
    reusing baseline: PersonalBaseline? = nil,
    preferring previousBaseline: PersonalBaseline? = nil
  ) -> Reading<HeartRateVariabilitySample> {
    assess(samples, using: .init(
      value: \.sdnnMilliseconds, date: \.date, method: .medianInComparablePeriod, calendar: calendar
    ), reusing: baseline, algorithmVersion: Self.hrvAlgorithmVersion, preferring: previousBaseline ?? baseline)
  }

  private func assess<Sample: Sendable>(
    _ samples: [SourcedHealthSample<Sample>],
    using aggregation: AggregateComparableHealthReadings<Sample>,
    reusing storedBaseline: PersonalBaseline?,
    algorithmVersion: Int,
    preferring previousBaseline: PersonalBaseline? = nil
  ) -> Reading<Sample> {
    let date = aggregation.date
    let cached = storedBaseline.flatMap { baseline -> PersonalBaseline? in
      guard baseline.algorithmVersion == algorithmVersion, baseline.windowStart == queryInterval.start,
            baseline.windowEnd == todayStart, baseline.timeZoneID == calendar.timeZone.identifier else { return nil }
      return baseline
    }
    let usable = samples.filter {
      let end = $0.sample[keyPath: date]
      return end >= queryInterval.start && end < queryInterval.end && aggregation.isUsable($0)
    }
    guard let reference = aggregation.latest(in: usable) else {
      let baseline = reusableBaseline(cached, reference: nil) ?? calculateBaseline(
        [],
        reference: nil,
        version: algorithmVersion
      )
      return Reading(latest: nil, assessment: .init(todayValue: nil, status: .building), baseline: baseline)
    }

    let referenceDate = reference.sample[keyPath: date]
    let latestReference = aggregation.reference(for: reference)
    let comparison = if aggregation.method == .medianInComparablePeriod {
      hrvReference(for: latestReference, in: usable, using: aggregation, cached: cached, preferring: previousBaseline)
    } else {
      latestReference
    }
    let reusable = reusableBaseline(cached, reference: comparison)
    let comparable = usable.filter { candidate in
      let candidateDate = candidate.sample[keyPath: date]
      return (reusable == nil || candidateDate >= todayStart) && aggregation.isComparable(candidate, to: comparison)
    }
    var daily = Dictionary(grouping: comparable) { calendar.startOfDay(for: $0.sample[keyPath: date]) }
      .compactMapValues { aggregation.dailyValue(in: $0) }

    let todayValue = daily.removeValue(forKey: todayStart)
    let baseline = reusable ?? calculateBaseline(
      daily.values.sorted(),
      reference: comparison,
      version: algorithmVersion
    )
    let status = Self.status(for: todayValue, baseline: baseline)
    let latest = referenceDate >= recentStart ? reference.sample : nil
    return Reading(latest: latest, assessment: .init(todayValue: todayValue, status: status), baseline: baseline)
  }

  private func hrvReference<Sample: Sendable>(
    for latest: ComparableHealthReference,
    in usable: [SourcedHealthSample<Sample>],
    using aggregation: AggregateComparableHealthReadings<Sample>,
    cached: PersonalBaseline?,
    preferring previousBaseline: PersonalBaseline?
  ) -> ComparableHealthReference {
    let previous = previousHRVReference(from: previousBaseline, matching: latest)
    // The verified revision and local window already establish this period's historical coverage.
    if let previous, let cached = reusableBaseline(cached, reference: previous), cached.validDayCount > 0,
       cached.validDayCount >= Self.minimumValidDays || previous.duration == latest.duration
    {
      return previous
    }

    var previousDays: Set<Date> = []
    var daysByPeriod = Array(repeating: Set<Date>(), count: 12)
    for reading in usable {
      let end = reading.sample[keyPath: aggregation.date]
      guard end < todayStart else { continue }
      let day = calendar.startOfDay(for: end)
      if let previous, aggregation.isComparable(reading, to: previous) {
        previousDays.insert(day)
      }
      if aggregation.matchesRecording(reading, to: latest) {
        daysByPeriod[aggregation.period(for: reading)].insert(day)
      }
    }
    if let previous, previousDays.count >= Self.minimumValidDays {
      return previous
    }

    // Count each historical day once. Iterating in clock order makes ties deterministic.
    var comparison = latest
    var bestCoverage = 0
    for (period, days) in daysByPeriod.enumerated() where days.count > bestCoverage {
      comparison.period = period
      bestCoverage = days.count
    }
    return comparison
  }

  private func previousHRVReference(
    from baseline: PersonalBaseline?,
    matching latest: ComparableHealthReference
  ) -> ComparableHealthReference? {
    guard let baseline, baseline.algorithmVersion == Self.hrvAlgorithmVersion,
          baseline.timeZoneID == calendar.timeZone.identifier,
          baseline.sourceIdentifier == latest.sourceIdentifier, baseline.deviceIdentifier == latest.deviceIdentifier,
          let period = baseline.referencePeriod, (0 ..< 12).contains(period),
          let duration = baseline.referenceDuration, duration.isFinite, duration >= 0 else { return nil }
    return ComparableHealthReference(
      sourceIdentifier: latest.sourceIdentifier, deviceIdentifier: latest.deviceIdentifier,
      period: period, duration: duration
    )
  }

  private func reusableBaseline(
    _ baseline: PersonalBaseline?,
    reference: ComparableHealthReference?
  ) -> PersonalBaseline? {
    guard let baseline,
          baseline.sourceIdentifier == reference?.sourceIdentifier,
          baseline.deviceIdentifier == reference?.deviceIdentifier,
          baseline.referencePeriod == reference?.period,
          baseline.referenceDuration == reference?.duration else { return nil }
    return baseline
  }

  private func calculateBaseline(
    _ sortedDailyValues: [Double],
    reference: ComparableHealthReference?,
    version: Int
  ) -> PersonalBaseline {
    let hasEnoughDays = sortedDailyValues.count >= Self.minimumValidDays
    return PersonalBaseline(
      p10: hasEnoughDays ? healthPercentile(0.1, of: sortedDailyValues) : nil,
      p50: hasEnoughDays ? healthPercentile(0.5, of: sortedDailyValues) : nil,
      p90: hasEnoughDays ? healthPercentile(0.9, of: sortedDailyValues) : nil,
      validDayCount: sortedDailyValues.count,
      windowStart: queryInterval.start,
      windowEnd: todayStart,
      timeZoneID: calendar.timeZone.identifier,
      sourceIdentifier: reference?.sourceIdentifier,
      deviceIdentifier: reference?.deviceIdentifier,
      referencePeriod: reference?.period,
      referenceDuration: reference?.duration,
      algorithmVersion: version,
      computedAt: .now
    )
  }

  private static func status(for todayValue: Double?, baseline: PersonalBaseline) -> TodayBaselineAssessment.Status {
    guard let range = range(for: baseline) else { return .building }
    guard let todayValue else { return .noCurrentReading }
    let position: TodayBaselineAssessment.Position = if todayValue < range.lowerBound {
      .belowRange
    } else if todayValue > range.upperBound {
      .aboveRange
    } else {
      .withinRange
    }
    return .compared(difference: todayValue - range.median, position: position)
  }

  static func range(for baseline: PersonalBaseline) -> HealthBaselineRange? {
    guard baseline.validDayCount >= minimumValidDays,
          let lower = baseline.p10, let median = baseline.p50, let upper = baseline.p90 else { return nil }
    return HealthBaselineRange(lowerBound: lower, median: median, upperBound: upper)
  }
}
