import AAGComponents
import AANModels
import AAODesignSystem
import SwiftUI

struct TodayMetricDetailScreen: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.locale) private var locale
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.timeZone) private var timeZone
  @State private var period = TodayChartPeriod.day

  let metric: TodayHealthMetric
  let model: TodayViewModel
  let day: DateInterval?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AppSpacing.regular) {
        if scenePhase == .background {
          ProgressView(.todayHealthLoading)
        } else if model.phase != .ready {
          TodayAppleHealthSection(model: model)
        } else if let day {
          chart(for: day)
        } else {
          TodayMetricReadError(model: model)
        }
        if metric == .heartRate {
          TodayHeartRateAbout()
        }
      }
      .frame(maxWidth: 560)
      .padding(AppPadding.regular)
      .frame(maxWidth: .infinity)
    }
    .scrollIndicators(.never, axes: .vertical)
    .safeAreaInset(edge: .top, spacing: 0) {
      Picker(selection: $period) {
        ForEach(TodayChartPeriod.allCases, id: \.self) { option in
          Text(verbatim: option.rawValue)
            .accessibilityLabel(spokenLabel(for: option))
            .tag(option)
        }
      } label: {
        Text(.todayChartTimeRange)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(maxWidth: 560)
      .padding(.horizontal, AppPadding.regular)
      .padding(.vertical, AppPadding.small)
      .frame(maxWidth: .infinity)
      .background(AppColors.groupedBackground)
    }
    .background(AppColors.groupedBackground)
    .tint(metric.tintColor)
    .navigationTitle(Text(metric.localizedTitle))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func spokenLabel(for period: TodayChartPeriod) -> Text {
    if let hours = period.hours {
      Text(Duration.seconds(hours * 3600), format: .units(allowed: [.hours], width: .wide))
    } else {
      Text(Duration.seconds(86400), format: .units(allowed: [.days], width: .wide))
    }
  }

  @ViewBuilder private func chart(for day: DateInterval) -> some View {
    if period == .day {
      chartSection(in: day)
    } else if let latest = model.measurement(for: metric).timestamp, (day.start ..< day.end).contains(latest) {
      chartSection(in: period.interval(in: day, anchoredAt: latest, calendar: calendar))
    } else {
      TimelineView(.everyMinute) { context in
        chartSection(in: period.interval(in: day, anchoredAt: context.date, calendar: calendar))
      }
    }
  }

  private func chartSection(in interval: DateInterval) -> some View {
    VStack(alignment: .leading, spacing: AppSpacing.small) {
      Text(interval.start, format: .dateTime.year().month(.wide).day())
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      if period != .day {
        Text((interval.start ..< interval.end).formatted(
          Date.IntervalFormatStyle(
            date: .omitted,
            time: .shortened,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
          )
        ))
        .font(.subheadline)
        .foregroundStyle(AppColors.secondaryText)
      }
      if model.measurement(for: metric) == .failed {
        TodayMetricReadError(model: model)
      } else if let refresh = model.verifiedRefresh(for: metric) {
        TodayMetricDayReadings(
          metric: metric,
          interval: interval,
          showsFullDay: period == .day,
          refresh: refresh,
          model: model
        )
        .id(interval)
        .id(refresh.verification)
      } else {
        ProgressView(.todayHealthLoading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(AppPadding.regular)
    .background(AppColors.groupedSurface, in: .rect(cornerRadius: 16))
  }
}

private struct TodayMetricDayReadings: View {
  enum Phase {
    case loading
    case readings([IntradayHealthPoint])
    case failed
  }

  @State private var phase = Phase.loading

  let metric: TodayHealthMetric
  let interval: DateInterval
  let showsFullDay: Bool
  let refresh: TodayViewModel.VerifiedRefresh
  let model: TodayViewModel

  var body: some View {
    Group {
      switch phase {
      case .loading:
        ProgressView(.todayHealthLoading)
      case let .readings(points):
        TodayMetricDayChart(
          metric: metric, interval: interval, showsFullDay: showsFullDay, points: points,
          emptyLabel: .todayHealthPeriodEmpty
        )
      case .failed:
        TodayMetricReadError(model: model)
      }
    }
    .task(id: refresh) {
      do {
        phase = try await .readings(model.readTimeline(for: metric, in: interval, refresh: refresh))
      } catch {
        guard !Task.isCancelled else { return }
        phase = .failed
      }
    }
  }
}

private struct TodayMetricReadError: View {
  let model: TodayViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.small) {
      Text(.todayHealthMetricFailed)
      Button(action: model.reload) {
        Text(.todayHealthRetry)
      }
      .buttonStyle(.bordered)
      .disabled(model.isLoading)
    }
  }
}
