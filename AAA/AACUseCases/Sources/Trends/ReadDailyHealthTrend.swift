import AAMStorages
import AANModels
import Foundation

struct ReadDailyHealthTrend: Sendable {
  private struct Mean {
    var value = 0.0
    var count = 0

    mutating func add(_ reading: Double) {
      count += 1
      value += (reading - value) / Double(count)
    }
  }

  let interval: DateInterval
  let calendar: Calendar
  let todayStart: Date
  private let queryInterval: DateInterval

  init?(now: Date, calendar: Calendar, retentionDays: Int?) {
    guard let today = calendar.dateInterval(of: .day, for: now),
          let firstDate = calendar.date(byAdding: .day, value: -29, to: today.start)
    else { return nil }
    let firstDay = calendar.startOfDay(for: firstDate)
    let retentionStart = retentionDays.flatMap {
      SynchronizeHealthHistory.retentionStart(days: $0, now: now, calendar: calendar)
    }
    interval = DateInterval(start: firstDay, end: today.end)
    queryInterval = DateInterval(start: max(firstDay, retentionStart ?? firstDay), end: now)
    todayStart = today.start
    self.calendar = calendar
  }

  func callAsFunction(_ metric: TodayHealthMetric, from store: HealthHistoryStore) async throws -> [DailyHealthValue] {
    let values: [Date: Double] = switch metric {
    case .heartRate:
      try await dailyHeartRate(from: store)
    case .heartRateVariability:
      try await dailyHeartRateVariability(from: store)
    case .restingHeartRate, .bloodOxygen, .respiratoryRate:
      try await store.reduceReadings(for: metric, in: queryInterval, into: [:]) { [calendar] values, sample in
        guard sample.value.isFinite, metric != .restingHeartRate || sample.value > 0 else { return }
        let day = calendar.startOfDay(for: sample.endDate)
        // The store enumerates newest first with stable ordering for equal timestamps.
        if values[day] == nil {
          values[day] = sample.value
        }
      }
    }
    return values.sorted { $0.key < $1.key }.map { DailyHealthValue(day: $0.key, value: $0.value) }
  }

  private func dailyHeartRate(from store: HealthHistoryStore) async throws -> [Date: Double] {
    let means = try await store.reduceReadings(
      for: .heartRate, in: queryInterval, into: [Date: Mean]()
    ) { [calendar] means, sample in
      guard sample.value.isFinite, sample.value > 0 else { return }
      means[calendar.startOfDay(for: sample.endDate), default: Mean()].add(sample.value)
    }
    return means.mapValues(\.value)
  }

  private func dailyHeartRateVariability(from store: HealthHistoryStore) async throws -> [Date: Double] {
    let aggregation = AggregateComparableHealthReadings<HeartRateVariabilitySample>(
      value: \.sdnnMilliseconds, date: \.date, method: .medianInComparablePeriod, calendar: calendar
    )
    let days = try await store.reduceReadings(
      for: .heartRateVariability, in: queryInterval, into: [Date: [SourcedHealthSample<HeartRateVariabilitySample>]]()
    ) { [calendar] days, sample in
      let reading = sample.sourced(HeartRateVariabilitySample(sdnnMilliseconds: sample.value, date: sample.endDate))
      days[calendar.startOfDay(for: sample.endDate), default: []].append(reading)
    }
    return days.compactMapValues { readings in
      let usable = readings.filter(aggregation.isUsable)
      guard let latest = usable.first else { return nil }
      let reference = aggregation.reference(for: latest)
      return aggregation.dailyValue(in: usable.filter { aggregation.isComparable($0, to: reference) })
    }
  }
}
