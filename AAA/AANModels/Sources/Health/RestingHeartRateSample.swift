import Foundation

/// A resting heart rate estimate from Apple Health.
public struct RestingHeartRateSample: Equatable, Sendable {
  public let beatsPerMinute: Double
  public let date: Date

  public init(beatsPerMinute: Double, date: Date) {
    self.beatsPerMinute = beatsPerMinute
    self.date = date
  }
}
