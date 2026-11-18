import Foundation

/// A blood oxygen saturation measurement (SpO₂).
public struct BloodOxygenSample: Equatable, Sendable {
  /// Oxygen saturation as a fraction from 0 to 1. For example, 0.98 represents 98%.
  public let saturation: Double

  /// The end time of the measurement.
  public let date: Date

  public init(saturation: Double, date: Date) {
    self.saturation = saturation
    self.date = date
  }
}
