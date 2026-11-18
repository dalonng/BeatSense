import AANModels
import Foundation
import SwiftData

extension HealthHistorySchemaV1 {
  @Model final class Baseline {
    @Attribute(.unique) var metricCode: String
    var inputRevision: UUID
    var p10: Double?
    var p50: Double?
    var p90: Double?
    var validDayCount: Int
    var windowStart: Date
    var windowEnd: Date
    var timeZoneID: String
    var sourceIdentifier: String?
    var deviceIdentifier: String?
    var referencePeriod: Int?
    var referenceDuration: TimeInterval?
    var algorithmVersion: Int
    var computedAt: Date

    init(metric: TodayHealthMetric, baseline: PersonalBaseline, revision: UUID) {
      metricCode = metric.rawValue
      inputRevision = revision
      p10 = baseline.p10
      p50 = baseline.p50
      p90 = baseline.p90
      validDayCount = baseline.validDayCount
      windowStart = baseline.windowStart
      windowEnd = baseline.windowEnd
      timeZoneID = baseline.timeZoneID
      sourceIdentifier = baseline.sourceIdentifier
      deviceIdentifier = baseline.deviceIdentifier
      referencePeriod = baseline.referencePeriod
      referenceDuration = baseline.referenceDuration
      algorithmVersion = baseline.algorithmVersion
      computedAt = baseline.computedAt
    }

    var value: PersonalBaseline {
      PersonalBaseline(
        p10: p10,
        p50: p50,
        p90: p90,
        validDayCount: validDayCount,
        windowStart: windowStart,
        windowEnd: windowEnd,
        timeZoneID: timeZoneID,
        sourceIdentifier: sourceIdentifier,
        deviceIdentifier: deviceIdentifier,
        referencePeriod: referencePeriod,
        referenceDuration: referenceDuration,
        algorithmVersion: algorithmVersion,
        computedAt: computedAt
      )
    }

    func update(from baseline: PersonalBaseline, revision: UUID) {
      inputRevision = revision
      p10 = baseline.p10
      p50 = baseline.p50
      p90 = baseline.p90
      validDayCount = baseline.validDayCount
      windowStart = baseline.windowStart
      windowEnd = baseline.windowEnd
      timeZoneID = baseline.timeZoneID
      sourceIdentifier = baseline.sourceIdentifier
      deviceIdentifier = baseline.deviceIdentifier
      referencePeriod = baseline.referencePeriod
      referenceDuration = baseline.referenceDuration
      algorithmVersion = baseline.algorithmVersion
      computedAt = baseline.computedAt
    }
  }
}
