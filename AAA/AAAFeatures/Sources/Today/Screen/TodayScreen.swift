import AACUseCases
import AANModels
import AAODesignSystem
import SwiftUI

struct TodayScreen: View {
  @Environment(\.scenePhase) private var scenePhase

  @State private var model: TodayViewModel
  @State private var isRetentionPresented = false
  @Binding private var retentionDays: Int

  private let healthChangeID: UUID?
  private let healthAuthorizationChangeID: UUID?
  private let today: DateInterval?

  init(
    refreshTodayHealth: RefreshTodayHealth,
    retentionDays: Binding<Int>,
    healthChangeID: UUID?,
    healthAuthorizationChangeID: UUID?,
    today: DateInterval?
  ) {
    _model = State(initialValue: TodayViewModel(refreshTodayHealth: refreshTodayHealth))
    _retentionDays = retentionDays
    self.healthChangeID = healthChangeID
    self.healthAuthorizationChangeID = healthAuthorizationChangeID
    self.today = today
  }

  var body: some View {
    let loadID = scenePhase == .background ? nil : model.loadID
    let shouldObserve = scenePhase == .active && model.canObserveHealthChanges
    let healthChangeID = shouldObserve ? model.healthChangeID : nil

    NavigationStack {
      ScrollView {
        VStack(spacing: AppSpacing.regular) {
          if model.phase == .ready {
            TodaySleepCard(model: model)
            TodayHealthMetricCard(metrics: [.restingHeartRate, .heartRateVariability], model: model, today: today)
            TodayHealthMetricCard(metrics: [.bloodOxygen], model: model, today: today)
            TodayHealthMetricCard(metrics: [.respiratoryRate], model: model, today: today)
            TodayHealthMetricCard(metrics: [.heartRate], model: model, today: today)
          } else {
            TodayAppleHealthSection(model: model)
          }
        }
        .frame(maxWidth: 560)
        .padding(AppPadding.regular)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.never, axes: .vertical)
      .background(AppColors.groupedBackground)
      .navigationTitle(Text(.tabToday))
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          TodayHealthRefreshButton(model: model)
          Button {
            isRetentionPresented = true
          } label: {
            Label(.healthHistoryRetentionTitle, systemImage: "gearshape")
              .labelStyle(.iconOnly)
          }
        }
      }
      .sheet(isPresented: $isRetentionPresented) {
        HealthHistoryRetentionScreen(retentionDays: $retentionDays)
      }
      .navigationDestination(for: TodayHealthMetric.self) { metric in
        TodayMetricDetailScreen(metric: metric, model: model, day: today)
      }
    }
    .task(id: loadID) {
      guard let loadID else { return }
      await model.load(id: loadID)
    }
    .task(id: healthChangeID) {
      guard let healthChangeID else { return }
      await model.refreshAfterHealthChange(id: healthChangeID)
    }
    .onChange(of: self.healthChangeID) {
      if scenePhase == .active {
        model.receiveHealthChange()
      }
    }
    .onChange(of: retentionDays) {
      model.revalidateReadings()
    }
    .onChange(of: healthAuthorizationChangeID) {
      if scenePhase == .active {
        model.revalidateReadings()
      }
    }
    .onChange(of: today) {
      if scenePhase == .active {
        model.revalidateReadings()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        model.revalidateReadings()
      } else if phase == .background {
        model.hideReadings()
      } else {
        model.discardPendingHealthRefresh()
      }
    }
    .onDisappear {
      model.discardPendingAuthorization()
      model.discardPendingHealthRefresh()
    }
  }
}

private struct TodayHealthRefreshButton: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var rotation = Angle.zero
  @State private var isSpinning = false

  let model: TodayViewModel

  var body: some View {
    let isLoading = model.isLoading

    Button {
      guard !isSpinning else { return }
      isSpinning = !reduceMotion
      model.reload()
    } label: {
      // Keep the animated image in the toolbar's SwiftUI view hierarchy.
      Color.clear
        .frame(width: 24, height: 24)
        .overlay {
          Image(systemName: "arrow.clockwise")
            .rotationEffect(rotation)
        }
        .contentShape(.rect)
    }
    .accessibilityLabel(Text(.todayHealthRefresh))
    .accessibilityValue(Text(.todayHealthLoading), isEnabled: isLoading)
    .disabled(model.phase != .ready || isLoading || isSpinning)
    .onChange(of: isLoading && !reduceMotion, initial: true) { _, shouldSpin in
      if shouldSpin {
        isSpinning = true
      }
    }
    .task(id: isSpinning && !reduceMotion) {
      await spinWhileRefreshing()
    }
  }

  private func spinWhileRefreshing() async {
    guard !Task.isCancelled else { return }

    if isSpinning, !reduceMotion {
      repeat {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          withAnimation(.linear(duration: 0.6), completionCriteria: .removed) {
            rotation.degrees += 360
          } completion: {
            continuation.resume()
          }
        }
        guard !Task.isCancelled else { return }
      } while model.isLoading
    }

    withAnimation(nil) {
      rotation = .zero
    }
    isSpinning = false
  }
}
