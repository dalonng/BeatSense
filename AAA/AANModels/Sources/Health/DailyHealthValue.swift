import Foundation

public struct DailyHealthValue: Equatable, Sendable, Identifiable {
  public let day: Date
  public let value: Double

  public var id: Date {
    day
  }

  public init(day: Date, value: Double) {
    self.day = day
    self.value = value
  }
}
