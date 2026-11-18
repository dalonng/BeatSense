import AACUseCases
import AAGComponents
import AANModels
import AAODesignSystem
import SwiftUI

struct TodayHealthMetricCard: View {
  let metrics: [TodayHealthMetric]
  let model: TodayViewModel
  let today: DateInterval?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(metrics, id: \.self) { metric in
        if metric != metrics.first {
          Divider()
            .padding(.horizontal, AppPadding.regular)
        }
        NavigationLink(value: metric) {
          TodayHealthMetricRow(metric: metric, model: model, today: today)
            .padding(AppPadding.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
      }
    }
    .fontDesign(.rounded)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppColors.groupedSurface, in: .rect(cornerRadius: 16))
  }
}

private struct TodayHealthMetricRow: View {
  let metric: TodayHealthMetric
  let model: TodayViewModel
  let today: DateInterval?

  var body: some View {
    let measurement = model.measurement(for: metric)
    TodayMetricRow(
      title: metric.localizedTitle,
      systemImage: metric.titleSystemImage,
      timestamp: measurement.timestamp,
      today: today
    ) {
      switch measurement {
      case .loading:
        ProgressView()
          .accessibilityLabel(Text(.todayHealthLoading))
      case .empty:
        Text(.todayHealthEmpty)
          .foregroundStyle(AppColors.secondaryText)
      case .failed:
        Text(.todayHealthMetricFailed)
          .foregroundStyle(AppColors.secondaryText)
      case let .heartRate(summary):
        TodayHeartRateSummary(summary: summary)
      case let .sample(value, _):
        TodayMetricValue(metric: metric, value: value, style: .prominent)
      case let .baselineSample(value, _, referenceMedian, status):
        if let value {
          if metric == .heartRateVariability {
            Text(.todayHealthLatestReading)
              .font(.caption)
              .foregroundStyle(AppColors.secondaryText)
          }
          TodayMetricValue(metric: metric, value: value, style: .prominent)
        } else {
          Text(.todayHealthEmpty)
            .foregroundStyle(AppColors.secondaryText)
        }
        if let referenceMedian {
          HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
            Text(.todayBaselineReferenceMedian)
            TodayMetricValue(metric: metric, value: referenceMedian, style: .statistic)
          }
          .font(.footnote)
          .foregroundStyle(AppColors.secondaryText)
        }
        TodayBaselineStatusView(metric: metric, status: status)
      }
    }
    .tint(metric.tintColor)
  }
}

private struct TodayBaselineStatusView: View {
  @Environment(\.locale) private var locale

  let metric: TodayHealthMetric
  let status: TodayBaselineAssessment.Status

  var body: some View {
    if case let .compared(difference, _) = status {
      let number = (abs(difference) <= 0.05 ? 0 : difference).formatted(
        .number.precision(.fractionLength(0 ... 1)).sign(strategy: .always(includingZero: false)).locale(locale)
      )
      Text(metric == .restingHeartRate ?
        .todayBaselineHeartRateDifference(number) : .todayBaselineHeartRateVariabilityDifference(number))
        .font(.footnote.monospacedDigit())
        .foregroundStyle(AppColors.secondaryText)
    }
    Text(label)
      .font(.footnote.weight(.medium))
      .foregroundStyle(statusColor)
  }

  private var label: LocalizedStringResource {
    switch status {
    case .building: .todayBaselineBuilding
    case .noCurrentReading:
      metric == .heartRateVariability ? .todayBaselineNoComparableReading : .todayBaselineNoCurrentReading
    case .compared(_, .belowRange): .todayBaselineBelowRange
    case .compared(_, .withinRange): .todayBaselineWithinRange
    case .compared(_, .aboveRange): .todayBaselineAboveRange
    }
  }

  private var statusColor: Color {
    switch status {
    case .building, .noCurrentReading: AppColors.secondaryText
    case .compared: AppColors.primaryText
    }
  }
}
