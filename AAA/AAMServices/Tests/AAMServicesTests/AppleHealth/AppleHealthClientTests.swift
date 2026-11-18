@testable import AAMServices
import AANModels
import Foundation
import HealthKit
import Testing

struct AppleHealthClientTests {
  @Test(arguments: [
    QuantityCase(metric: .bloodOxygen, identifier: .oxygenSaturation, unit: .percent(), value: 0.975, expected: 0.975),
    QuantityCase(
      metric: .respiratoryRate,
      identifier: .respiratoryRate,
      unit: .count().unitDivided(by: .second()),
      value: 0.25,
      expected: 15
    ),
    QuantityCase(
      metric: .heartRateVariability,
      identifier: .heartRateVariabilitySDNN,
      unit: .second(),
      value: 0.048,
      expected: 48
    ),
    QuantityCase(
      metric: .restingHeartRate,
      identifier: .restingHeartRate,
      unit: .count().unitDivided(by: .second()),
      value: 1,
      expected: 60
    ),
  ]) func `converts a scalar sample with its identity, interval, and normalized unit`(input: QuantityCase) async throws {
    let start = Date(timeIntervalSinceReferenceDate: 100)
    let end = start.addingTimeInterval(4)
    let sample = HKQuantitySample(
      type: HKQuantityType(input.identifier),
      quantity: HKQuantity(unit: input.unit, doubleValue: input.value),
      start: start,
      end: end
    )

    let measurements = try await AppleHealthClient.measurements(
      for: input.metric,
      samples: [sample],
      store: HKHealthStore()
    )
    let measurement = try #require(measurements.first)
    #expect(measurements.count == 1)
    #expect(measurement.metric == input.metric)
    #expect(measurement.healthKitUUID == sample.uuid)
    #expect(measurement.ordinal == 0)
    #expect(measurement.startDate == start)
    #expect(measurement.endDate == end)
    #expect(measurement.value == input.expected)
    #expect(measurement.sourceIdentifier == sample.sourceRevision.source.bundleIdentifier)
  }

  @Test func `read authorization includes sleep and every history quantity type`() throws {
    let types: [(TodayHealthMetric, HKQuantityTypeIdentifier)] = [
      (.heartRate, .heartRate),
      (.bloodOxygen, .oxygenSaturation),
      (.respiratoryRate, .respiratoryRate),
      (.restingHeartRate, .restingHeartRate),
      (.heartRateVariability, .heartRateVariabilitySDNN),
    ]
    let quantityTypes = Set(types.map { HKQuantityType($0.1) as HKObjectType })
    let sleepTypes: Set<HKObjectType> = [HKCategoryType(.sleepAnalysis)]
    #expect(AppleHealthReadScope.measurements.readTypes == quantityTypes)
    #expect(AppleHealthReadScope.sleep.readTypes == sleepTypes)
    #expect(AppleHealthReadScope.all.readTypes == quantityTypes.union(sleepTypes))
    let start = Date(timeIntervalSinceReferenceDate: 100)
    let anchor = HKQueryAnchor(fromValue: 42)
    for (metric, identifier) in types {
      let query = AppleHealthClient.historyQuery(for: metric, since: start, anchor: anchor)
      let predicate = try #require(query.predicates.first)
      #expect(predicate.sampleType == HKQuantityType(identifier))
      #expect(query.limit == 256)
      #expect(query.anchor == anchor)
    }
  }

  @Test func `a history predicate includes overlapping parents and has no fixed upper bound`() throws {
    let start = Date(timeIntervalSinceReferenceDate: 100)
    let query = AppleHealthClient.historyQuery(for: .heartRate, since: start, anchor: nil)
    let samplePredicate = try #require(query.predicates.first)
    let predicate = try #require(samplePredicate.nsPredicate)
    let prior = start.addingTimeInterval(-2)
    let future = start.addingTimeInterval(1000)
    #expect(predicate.evaluate(with: makeHeartRate(start: prior, end: start)))
    #expect(predicate.evaluate(with: makeHeartRate(start: future, end: future)))
    #expect(!predicate.evaluate(with: makeHeartRate(start: prior, end: start.addingTimeInterval(-1))))
  }

  @Test func `the stored anchor round-trips and unreadable data is reported separately`() throws {
    let anchor = HKQueryAnchor(fromValue: 42)
    let encoded = try AppleHealthClient.encodeAnchor(anchor)
    #expect(try AppleHealthClient.decodeAnchor(encoded) == anchor)
    #expect(throws: AppleHealthError.invalidAnchor) {
      try AppleHealthClient.decodeAnchor(Data())
    }
  }

  @Test func `a pre-cancelled request throws before decoding its anchor`() async {
    let client = AppleHealthClient()
    await withTaskGroup(of: Void.self) { group in
      group.cancelAll()
      group.addTask {
        await #expect(throws: CancellationError.self) {
          try await client.sampleChanges(for: .heartRate, since: .distantPast, anchor: Data(), reusing: [])
        }
      }
    }
  }

  private func makeHeartRate(start: Date, end: Date) -> HKQuantitySample {
    HKQuantitySample(
      type: HKQuantityType(.heartRate),
      quantity: HKQuantity(unit: .count().unitDivided(by: .second()), doubleValue: 1.25),
      start: start,
      end: end
    )
  }

  struct QuantityCase: Sendable {
    let metric: TodayHealthMetric
    let identifier: HKQuantityTypeIdentifier
    let unit: HKUnit
    let value: Double
    let expected: Double
  }
}
