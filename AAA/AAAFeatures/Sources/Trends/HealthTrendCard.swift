import AACUseCases
import AAGComponents
import AANModels
import AAODesignSystem
import SwiftUI

struct HealthTrendCard: View {
  let metric: TodayHealthMetric
  let series: RefreshHealthTrends.Series
  let baseline: HealthBaselineRange?
  let interval: DateInterval
  let calendar: Calendar
  let isLoading: Bool
  let retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.small) {
      VStack(alignment: .leading, spacing: AppSpacing.tiny) {
        Label {
          Text(metric.localizedTitle)
            .foregroundStyle(.tint)
        } icon: {
          Image(systemName: metric.titleSystemImage)
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
        }
        .font(.headline)
        .accessibilityAddTraits(.isHeader)

        Text(aggregation)
          .font(.subheadline)
          .foregroundStyle(AppColors.secondaryText)
      }

      switch series {
      case let .readings(readings):
        let visibleReadings = readings.filter { interval.start <= $0.day && $0.day < interval.end }
        if visibleReadings.isEmpty {
          Text(.trendsEmpty)
            .foregroundStyle(AppColors.secondaryText)
        }
        if !visibleReadings.isEmpty || baseline != nil {
          HealthTrendChart(
            metric: metric,
            title: metric.localizedTitle,
            noReadingLabel: .trendsNoReading,
            readings: visibleReadings,
            interval: interval,
            calendar: calendar,
            baseline: baseline.map {
              .init(range: $0, medianLabel: .trendsBaseline, usualRangeLabel: .trendsUsualRange)
            }
          )
        }
        if baseline == nil, metric == .restingHeartRate || metric == .heartRateVariability {
          Text(.todayBaselineBuilding)
            .font(.footnote)
            .foregroundStyle(AppColors.secondaryText)
        }
      case .failed:
        Text(.todayHealthMetricFailed)
          .foregroundStyle(AppColors.secondaryText)
        Button(action: retry) {
          Text(.todayHealthRetry)
        }
        .buttonStyle(.bordered)
        .disabled(isLoading)
      }
    }
    .fontDesign(.rounded)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(AppPadding.regular)
    .background(AppColors.groupedSurface, in: .rect(cornerRadius: 16))
    .tint(metric.tintColor)
  }

  private var aggregation: LocalizedStringResource {
    switch metric {
    case .heartRate: .trendsDailyAverage
    case .heartRateVariability: .trendsDailyMedian
    case .restingHeartRate, .bloodOxygen, .respiratoryRate: .trendsDailyLatest
    }
  }
}
