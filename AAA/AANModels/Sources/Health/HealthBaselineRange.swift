/// A personal median and the lower and upper bounds of its usual range.
public struct HealthBaselineRange: Equatable, Sendable {
  public let lowerBound: Double
  public let median: Double
  public let upperBound: Double

  public init?(lowerBound: Double, median: Double, upperBound: Double) {
    guard lowerBound.isFinite, median.isFinite, upperBound.isFinite,
          lowerBound <= median, median <= upperBound else { return nil }
    self.lowerBound = lowerBound
    self.median = median
    self.upperBound = upperBound
  }
}
