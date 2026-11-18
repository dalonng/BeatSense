import AANModels
import Foundation
import HealthKit

extension AppleHealthClient {
  public func sampleChanges(
    for metric: TodayHealthMetric,
    since start: Date,
    anchor: Data?,
    reusing sampleIDs: Set<UUID>
  ) async throws -> HealthSampleBatch {
    try Task.checkCancellation()
    guard start.timeIntervalSinceReferenceDate.isFinite else { throw AppleHealthError.queryFailed }
    let position = try anchor.map(Self.decodeAnchor)
    let store = try availableStore()
    let query = Self.historyQuery(for: metric, since: start, anchor: position)
    let page: HKAnchoredObjectQueryDescriptor<HKQuantitySample>.Result
    do {
      page = try await query.result(for: store)
    } catch let error as HKError where error.code == .errorNoData {
      try Task.checkCancellation()
      let currentAnchor = try anchor ?? Self.encodeAnchor(HKQueryAnchor(fromValue: 0))
      return HealthSampleBatch(measurements: [], seenSampleIDs: [], deletedSampleIDs: [], anchor: currentAnchor)
    } catch let error as HKError where error.code == .errorInvalidArgument && position != nil {
      try Task.checkCancellation()
      throw AppleHealthError.invalidAnchor
    } catch {
      throw Self.serviceError(for: error, fallback: .queryFailed)
    }

    do {
      try Task.checkCancellation()
      let deletedIDs = page.deletedObjects.map(\.uuid)
      let skippedIDs = sampleIDs.union(deletedIDs)
      let newSamples = page.addedSamples.filter { !skippedIDs.contains($0.uuid) }
      let measurements = try await Self.measurements(for: metric, samples: newSamples, store: store)
      try Task.checkCancellation()
      return try HealthSampleBatch(
        measurements: measurements,
        seenSampleIDs: page.addedSamples.map(\.uuid),
        deletedSampleIDs: deletedIDs,
        anchor: Self.encodeAnchor(page.newAnchor)
      )
    } catch {
      throw Self.serviceError(for: error, fallback: .queryFailed)
    }
  }

  public func earliestAuthorizedSampleDates() async throws -> [TodayHealthMetric: Date] {
    try Task.checkCancellation()
    let store = try availableStore()
    guard #available(iOS 27.0, *) else { return [:] }
    do {
      let dates = try await store.earliestAuthorizedSampleDate(for: AppleHealthReadScope.measurements.readTypes)
      try Task.checkCancellation()
      return TodayHealthMetric.allCases.reduce(into: [:]) { result, metric in
        result[metric] = dates[metric.quantityType]
      }
    } catch {
      throw Self.serviceError(for: error, fallback: .queryFailed)
    }
  }

  static func historyQuery(
    for metric: TodayHealthMetric,
    since start: Date,
    anchor: HKQueryAnchor?
  ) -> HKAnchoredObjectQueryDescriptor<HKQuantitySample> {
    // Match overlapping parents so a series spanning the lower bound can be imported.
    let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
    return HKAnchoredObjectQueryDescriptor(
      predicates: [.quantitySample(type: metric.quantityType, predicate: predicate)],
      anchor: anchor,
      limit: 256
    )
  }

  static func encodeAnchor(_ anchor: HKQueryAnchor) throws -> Data {
    try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
  }

  static func decodeAnchor(_ data: Data) throws -> HKQueryAnchor {
    do {
      if let anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data) {
        return anchor
      }
    } catch {
      throw AppleHealthError.invalidAnchor
    }
    throw AppleHealthError.invalidAnchor
  }

  static func measurements(
    for metric: TodayHealthMetric,
    samples: [HKQuantitySample],
    store: HKHealthStore
  ) async throws -> [HealthMeasurement] {
    // Preserve the detailed interval for single-entry heart rate series as well.
    let series = samples.filter { metric == .heartRate || $0.count > 1 }
    var details = try await seriesEntries(for: metric, samples: series, store: store)
    let unit = metric.unit
    var measurements: [HealthMeasurement] = []
    for sample in samples {
      try Task.checkCancellation()
      let entries: [QuantityEntry]
      if metric != .heartRate, sample.count == 1 {
        entries = [
          QuantityEntry(
            interval: DateInterval(start: sample.startDate, end: sample.endDate),
            value: sample.quantity.doubleValue(for: unit)
          ),
        ]
      } else {
        // A parent can disappear or lose visibility between the anchored and series queries.
        // Leave the checkpoint unchanged so the next anchored query can retry the page.
        guard let detail = details.removeValue(forKey: sample.uuid),
              !detail.isEmpty else { throw AppleHealthError.queryFailed }
        entries = detail.sorted(by: QuantityEntry.precedes)
      }

      for (ordinal, entry) in entries.enumerated() where entry.value.isFinite {
        measurements.append(entry.measurement(sample: sample, metric: metric, ordinal: ordinal))
      }
    }
    return measurements
  }

  private static func seriesEntries(
    for metric: TodayHealthMetric,
    samples: [HKQuantitySample],
    store: HKHealthStore
  ) async throws -> [UUID: [QuantityEntry]] {
    guard !samples.isEmpty else { return [:] }
    let ids = Set(samples.map(\.uuid))
    let query = HKQuantitySeriesSampleQueryDescriptor(
      predicate: .quantitySample(type: metric.quantityType, predicate: HKQuery.predicateForObjects(with: ids)),
      options: .includeSample
    )
    var entries: [UUID: [QuantityEntry]] = [:]
    let unit = metric.unit
    for try await result in query.results(for: store) {
      try Task.checkCancellation()
      guard let parent = result.sample, ids.contains(parent.uuid) else { throw AppleHealthError.queryFailed }
      entries[parent.uuid, default: []].append(QuantityEntry(
        interval: result.dateInterval,
        value: result.quantity.doubleValue(for: unit)
      ))
    }
    return entries
  }
}

private struct QuantityEntry {
  let interval: DateInterval
  let value: Double

  static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
    if lhs.interval.end != rhs.interval.end {
      return lhs.interval.end < rhs.interval.end
    }
    if lhs.interval.start != rhs.interval.start {
      return lhs.interval.start < rhs.interval.start
    }
    return lhs.value.bitPattern < rhs.value.bitPattern
  }

  func measurement(sample: HKQuantitySample, metric: TodayHealthMetric, ordinal: Int) -> HealthMeasurement {
    HealthMeasurement(
      metric: metric,
      healthKitUUID: sample.uuid,
      ordinal: ordinal,
      startDate: interval.start,
      endDate: interval.end,
      value: value,
      sourceIdentifier: sample.sourceRevision.source.bundleIdentifier,
      deviceIdentifier: sample.device?.localIdentifier ?? sample.sourceRevision.productType
    )
  }
}

extension TodayHealthMetric {
  var quantityType: HKQuantityType {
    switch self {
    case .heartRate: HKQuantityType(.heartRate)
    case .bloodOxygen: HKQuantityType(.oxygenSaturation)
    case .respiratoryRate: HKQuantityType(.respiratoryRate)
    case .restingHeartRate: HKQuantityType(.restingHeartRate)
    case .heartRateVariability: HKQuantityType(.heartRateVariabilitySDNN)
    }
  }

  fileprivate var unit: HKUnit {
    switch self {
    case .heartRate, .respiratoryRate, .restingHeartRate: HKUnit.count().unitDivided(by: .minute())
    case .bloodOxygen: .percent()
    case .heartRateVariability: .secondUnit(with: .milli)
    }
  }
}
