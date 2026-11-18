import AANModels
import Foundation
import SwiftData

enum HealthHistorySchemaV1: VersionedSchema {
  static let versionIdentifier = Schema.Version(1, 0, 0)
  static let models: [any PersistentModel.Type] = [Measurement.self, SyncState.self, Baseline.self]

  @Model final class Measurement {
    #Unique<Measurement>([\.healthKitUUID, \.ordinal])
    #Index<Measurement>([\.metricCode, \.endDate], [\.endDate])

    var metricCode: String
    var healthKitUUID: UUID
    var ordinal: Int
    var startDate: Date
    var endDate: Date
    var value: Double
    var sourceIdentifier: String
    var deviceIdentifier: String?
    var canReuse: Bool

    init(_ sample: HealthMeasurement, canReuse: Bool) {
      metricCode = sample.metric.rawValue
      healthKitUUID = sample.healthKitUUID
      ordinal = sample.ordinal
      startDate = sample.startDate
      endDate = sample.endDate
      value = sample.value
      sourceIdentifier = sample.sourceIdentifier
      deviceIdentifier = sample.deviceIdentifier
      self.canReuse = canReuse
    }

    func measurement(for metric: TodayHealthMetric) -> HealthMeasurement {
      HealthMeasurement(
        metric: metric,
        healthKitUUID: healthKitUUID,
        ordinal: ordinal,
        startDate: startDate,
        endDate: endDate,
        value: value,
        sourceIdentifier: sourceIdentifier,
        deviceIdentifier: deviceIdentifier
      )
    }

    func update(from sample: HealthMeasurement) {
      startDate = sample.startDate
      endDate = sample.endDate
      value = sample.value
      sourceIdentifier = sample.sourceIdentifier
      deviceIdentifier = sample.deviceIdentifier
    }
  }

  @Model final class SyncState {
    @Attribute(.unique) var metricCode: String
    var generation: UUID
    var anchor: Data?
    var queryStart: Date
    var completedCutoff: Date?
    var inputRevision: UUID

    init(metric: TodayHealthMetric, generation: UUID, queryStart: Date) {
      metricCode = metric.rawValue
      self.generation = generation
      self.queryStart = queryStart
      inputRevision = UUID()
    }
  }
}
