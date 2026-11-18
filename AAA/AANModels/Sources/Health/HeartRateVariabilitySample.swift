import Foundation

/// A heart rate variability measurement using SDNN.
public struct HeartRateVariabilitySample: Equatable, Sendable {
  /// The standard deviation of normal-to-normal heartbeat intervals, in milliseconds.
  public let sdnnMilliseconds: Double

  /// The end time of the measurement.
  public let date: Date

  public init(sdnnMilliseconds: Double, date: Date) {
    self.sdnnMilliseconds = sdnnMilliseconds
    self.date = date
  }
}
