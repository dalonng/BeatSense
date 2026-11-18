import AANModels
import AAODesignSystem
import SwiftUI

public struct TodayHeartRateSummary: View {
  private let summary: HeartRateSummary

  public init(summary: HeartRateSummary) {
    self.summary = summary
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.regular) {
      if summary.sampleCount > 0 {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
          Text(.todayHeartRateDistribution)
            .font(.subheadline.weight(.medium))
          TodayHeartRateDistribution(summary: summary)
        }
        Divider()
      }

      VStack(alignment: .leading, spacing: AppSpacing.tiny) {
        Text(.todayHeartRateLatest)
          .font(.subheadline.weight(.medium))
        TodayMetricValue(metric: .heartRate, value: summary.latest.beatsPerMinute, style: .prominent)
      }
      .accessibilityElement(children: .combine)

      Grid(alignment: .leading, horizontalSpacing: AppSpacing.regular, verticalSpacing: AppSpacing.small) {
        statistic(.todayHeartRateAverage, bpm: summary.averageBPM)
        statistic(.todayHeartRateMaximum, bpm: summary.maximumBPM)
        statistic(.todayHeartRateMinimum, bpm: summary.minimumBPM)
      }
      .font(.subheadline)
    }
  }

  private func statistic(_ title: LocalizedStringResource, bpm: Double) -> some View {
    GridRow {
      Text(title)
      TodayMetricValue(metric: .heartRate, value: bpm, style: .statistic)
        .gridColumnAlignment(.trailing)
    }
    .accessibilityElement(children: .combine)
  }
}
