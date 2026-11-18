import Foundation

public struct HealthMeasurement: Equatable, Sendable {
  public let metric: TodayHealthMetric
  public let healthKitUUID: UUID
  public let ordinal: Int
  public let startDate: Date
  public let endDate: Date
  public let value: Double
  public let sourceIdentifier: String
  public let deviceIdentifier: String?

  public init(
    metric: TodayHealthMetric,
    healthKitUUID: UUID,
    ordinal: Int,
    startDate: Date,
    endDate: Date,
    value: Double,
    sourceIdentifier: String,
    deviceIdentifier: String?
  ) {
    self.metric = metric
    self.healthKitUUID = healthKitUUID
    self.ordinal = ordinal
    self.startDate = startDate
    self.endDate = endDate
    self.value = value
    self.sourceIdentifier = sourceIdentifier
    self.deviceIdentifier = deviceIdentifier
  }
}
