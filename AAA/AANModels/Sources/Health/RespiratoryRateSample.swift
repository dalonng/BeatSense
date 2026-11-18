import Foundation

/// A respiratory rate measurement.
public struct RespiratoryRateSample: Equatable, Sendable {
  /// The measured respiratory rate in breaths per minute.
  public let breathsPerMinute: Double

  /// The end time of the measurement.
  public let date: Date

  public init(breathsPerMinute: Double, date: Date) {
    self.breathsPerMinute = breathsPerMinute
    self.date = date
  }
}
