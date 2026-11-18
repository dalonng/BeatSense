import AAGComponents
import AAODesignSystem
import SwiftUI

struct TodaySleepCard: View {
  let model: TodayViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.medium) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: AppSpacing.medium) {
          title
          reading
        }
        .fixedSize(horizontal: true, vertical: false)
        VStack(alignment: .leading, spacing: AppSpacing.small) {
          title
          reading
        }
      }
      if case let .summary(summary) = model.sleepState {
        Divider()
        TodaySleepStages(stageDurations: summary.stageDurations)
      }
    }
    .fontDesign(.rounded)
    .padding(AppPadding.regular)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppColors.groupedSurface, in: .rect(cornerRadius: 16))
  }

  private var title: some View {
    Label {
      Text(.todayHealthSleep)
    } icon: {
      Image(systemName: "bed.double.fill")
        .foregroundStyle(.teal)
    }
    .font(.headline)
    .accessibilityAddTraits(.isHeader)
  }

  @ViewBuilder private var reading: some View {
    switch model.sleepState {
    case let .summary(summary):
      TodaySleepMetrics(summary: summary)
    case .loading:
      ProgressView()
        .accessibilityLabel(Text(.todayHealthLoading))
    case .needsConnection:
      Button(action: model.connectSleep) {
        Text(.todaySleepConnect)
      }
      .buttonStyle(.bordered)
      .disabled(model.isLoading)
    case .empty:
      Text(.todaySleepEmpty)
        .foregroundStyle(AppColors.secondaryText)
    case .failed:
      VStack(alignment: .leading, spacing: AppSpacing.small) {
        Text(.todayHealthMetricFailed)
          .foregroundStyle(AppColors.secondaryText)
        Button(action: model.reload) {
          Text(.todayHealthRetry)
        }
        .buttonStyle(.bordered)
        .disabled(model.isLoading)
      }
    }
  }
}
