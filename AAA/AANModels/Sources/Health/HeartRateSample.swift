import Foundation

/// A heart rate measurement.
public struct HeartRateSample: Equatable, Sendable {
  /// The measured heart rate in beats per minute.
  public let beatsPerMinute: Double

  /// The end time of the measurement.
  public let date: Date

  public init(beatsPerMinute: Double, date: Date) {
    self.beatsPerMinute = beatsPerMinute
    self.date = date
  }
}
