import Foundation

/// A derived baseline for the complete local days in `[windowStart, windowEnd)`.
public struct PersonalBaseline: Equatable, Sendable {
  public let p10: Double?
  public let p50: Double?
  public let p90: Double?
  public let validDayCount: Int
  public let windowStart: Date
  public let windowEnd: Date
  public let timeZoneID: String
  public let sourceIdentifier: String?
  public let deviceIdentifier: String?
  public let referencePeriod: Int?
  public let referenceDuration: TimeInterval?
  public let algorithmVersion: Int
  public let computedAt: Date

  public init(
    p10: Double?,
    p50: Double?,
    p90: Double?,
    validDayCount: Int,
    windowStart: Date,
    windowEnd: Date,
    timeZoneID: String,
    sourceIdentifier: String?,
    deviceIdentifier: String?,
    referencePeriod: Int?,
    referenceDuration: TimeInterval?,
    algorithmVersion: Int,
    computedAt: Date
  ) {
    self.p10 = p10
    self.p50 = p50
    self.p90 = p90
    self.validDayCount = validDayCount
    self.windowStart = windowStart
    self.windowEnd = windowEnd
    self.timeZoneID = timeZoneID
    self.sourceIdentifier = sourceIdentifier
    self.deviceIdentifier = deviceIdentifier
    self.referencePeriod = referencePeriod
    self.referenceDuration = referenceDuration
    self.algorithmVersion = algorithmVersion
    self.computedAt = computedAt
  }
}
