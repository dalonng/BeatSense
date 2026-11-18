import AACUseCases
import AANModels
import AAODesignSystem
import SwiftUI

struct TrendsScreen: View {
  private enum Period: Int, CaseIterable {
    case sevenDays = 7
    case thirtyDays = 30

    var label: LocalizedStringResource {
      switch self {
      case .sevenDays: .trendsSevenDays
      case .thirtyDays: .trendsThirtyDays
      }
    }
  }

  @Environment(\.locale) private var locale
  @Environment(\.scenePhase) private var scenePhase
  @State private var period = Period.thirtyDays

  let model: TrendsViewModel
  let retentionDays: Int

  var body: some View {
    let loadID = scenePhase == .background ? nil : model.loadID
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
          if case let .ready(snapshot) = model.phase, scenePhase != .background {
            let interval = visibleInterval(in: snapshot)
            Text(dateRange(interval, calendar: snapshot.calendar))
              .font(.subheadline)
              .foregroundStyle(AppColors.secondaryText)

            ForEach(TodayHealthMetric.allCases, id: \.self) { metric in
              HealthTrendCard(
                metric: metric,
                series: snapshot.series[metric] ?? .failed,
                baseline: snapshot.baselines[metric],
                interval: interval,
                calendar: snapshot.calendar,
                isLoading: model.isLoading,
                retry: model.reload
              )
            }
          } else {
            status
          }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(AppPadding.regular)
        .frame(maxWidth: .infinity)
      }
      .safeAreaInset(edge: .top, spacing: 0) {
        Picker(selection: $period) {
          ForEach(Period.allCases, id: \.self) { period in
            Text(period.label)
              .tag(period)
          }
        } label: {
          Text(.trendsDateRange)
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
      .navigationTitle(Text(.tabTrends))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if case .ready = model.phase {
          ToolbarItem(placement: .topBarTrailing) {
            Button(action: model.reload) {
              Label(.todayHealthRefresh, systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
            }
            .accessibilityValue(Text(.todayHealthLoading), isEnabled: model.isLoading)
            .disabled(model.isLoading)
          }
        }
      }
    }
    .task(id: loadID) {
      guard let loadID else { return }
      await model.load(id: loadID, retentionDays: retentionDays)
    }
    .onDisappear(perform: model.cancelConnection)
  }

  private var status: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: AppSpacing.medium) {
        switch model.phase {
        case .loading, .ready:
          ProgressView {
            Text(.todayHealthLoading)
          }
        case .needsConnection:
          Text(.trendsConnectDescription)
          Button(action: model.connect) {
            Text(.todayHealthConnect)
          }
          .buttonStyle(.borderedProminent)
        case .unavailable:
          Text(.todayHealthUnavailable)
        case .restricted:
          Text(.todayHealthRestricted)
        case .failed:
          Text(.todayHealthFailed)
          Button(action: model.reload) {
            Text(.todayHealthRetry)
          }
          .buttonStyle(.bordered)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func visibleInterval(in snapshot: RefreshHealthTrends.Snapshot) -> DateInterval {
    let interval = snapshot.interval
    let calendar = snapshot.calendar
    guard period == .sevenDays,
          let firstDay = calendar.date(byAdding: .day, value: -period.rawValue, to: interval.end)
    else { return interval }
    return DateInterval(start: calendar.startOfDay(for: firstDay), end: interval.end)
  }

  private func dateRange(_ interval: DateInterval, calendar: Calendar) -> String {
    let today = calendar.startOfDay(for: interval.end - 1)
    return (interval.start ..< today).formatted(
      Date.IntervalFormatStyle(
        date: .abbreviated,
        time: .omitted,
        locale: locale,
        calendar: calendar,
        timeZone: calendar.timeZone
      )
    )
  }
}
