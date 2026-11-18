import AANModels
import AAODesignSystem
import SwiftUI

struct TodayHeartRateDistribution: View {
  @Environment(\.locale) private var locale

  let summary: HeartRateSummary

  var body: some View {
    let sampleCount = summary.sampleCount
    VStack(alignment: .leading, spacing: AppSpacing.small) {
      Text(.todayHeartRateDistributionCaption)
        .font(.caption)
        .foregroundStyle(AppColors.secondaryText)

      if sampleCount > 0 {
        ForEach(summary.buckets, id: \.lowerBoundBPM) { bucket in
          let share = Double(bucket.count) / Double(sampleCount)
          VStack(alignment: .leading, spacing: AppSpacing.tiny) {
            HStack(alignment: .firstTextBaseline) {
              Text(rangeLabel(bucket))
              Spacer(minLength: AppSpacing.small)
              Text(share, format: .percent.precision(.fractionLength(0 ... 1)))
                .monospacedDigit()
            }
            .font(.caption)
            ProgressView(value: share)
              .accessibilityHidden(true)
          }
          .accessibilityElement(children: .combine)
        }
      }
    }
  }

  private func rangeLabel(_ bucket: HeartRateSummary.Bucket) -> LocalizedStringResource {
    let lower = bucket.lowerBoundBPM.formatted(.number.locale(locale))
    if let upper = bucket.upperBoundBPM {
      return .todayHeartRateRange(lower, upper.formatted(.number.locale(locale)))
    }
    return .todayHeartRateOpenRange(lower)
  }
}
