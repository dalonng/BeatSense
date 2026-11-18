import Foundation

public struct HealthSampleBatch: Sendable {
  public let measurements: [HealthMeasurement]
  public let seenSampleIDs: [UUID]
  public let deletedSampleIDs: [UUID]
  public let anchor: Data

  public init(measurements: [HealthMeasurement], seenSampleIDs: [UUID], deletedSampleIDs: [UUID], anchor: Data) {
    self.measurements = measurements
    self.seenSampleIDs = seenSampleIDs
    self.deletedSampleIDs = deletedSampleIDs
    self.anchor = anchor
  }
}
