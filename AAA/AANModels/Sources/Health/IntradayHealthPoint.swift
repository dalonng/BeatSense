import Foundation

/// A measured value in the metric's native unit, plotted at the sample's end time.
public struct IntradayHealthPoint: Equatable, Sendable {
  public let date: Date
  public let value: Double

  public init(date: Date, value: Double) {
    self.date = date
    self.value = value
  }
}
