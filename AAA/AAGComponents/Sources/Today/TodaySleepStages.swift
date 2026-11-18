import AANModels
import AAODesignSystem
import SwiftUI

public struct TodaySleepStages: View {
  private let stageDurations: [SleepSample.State: TimeInterval]

  public init(stageDurations: [SleepSample.State: TimeInterval]) {
    self.stageDurations = stageDurations
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.small) {
      if stageDurations[.deep] != nil || stageDurations[.core] != nil || stageDurations[.rem] != nil {
        stage(.deep, title: .todaySleepStageDeep, color: .indigo)
        stage(.core, title: .todaySleepStageCore, color: .blue)
        stage(.rem, title: .todaySleepStageRem, color: .cyan)
        stage(.asleep, title: .todaySleepStageUnspecified, color: .secondary)
      } else {
        Text(.todaySleepStageUnavailable)
          .foregroundStyle(AppColors.secondaryText)
      }
      stage(.awake, title: .todaySleepStageAwake, color: .orange)
    }
    .font(.subheadline)
  }

  @ViewBuilder private func stage(
    _ state: SleepSample.State,
    title: LocalizedStringResource,
    color: Color
  ) -> some View {
    if let seconds = stageDurations[state] {
      SleepStageRow(title: title, color: color, seconds: seconds)
    }
  }
}

private struct SleepStageRow: View {
  let title: LocalizedStringResource
  let color: Color
  let seconds: TimeInterval

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
        .accessibilityHidden(true)
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline) {
          Text(title).fixedSize()
          Spacer(minLength: AppSpacing.small)
          duration(width: .abbreviated).fixedSize()
        }
        VStack(alignment: .leading, spacing: AppSpacing.micro) {
          Text(title)
          duration(width: .abbreviated)
        }
      }
    }
    .monospacedDigit()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(title))
    .accessibilityValue(duration(width: .wide))
  }

  private func duration(width: Duration.UnitsFormatStyle.UnitWidth) -> Text {
    if seconds < 60 {
      return Text(.todaySleepStageUnderMinute)
    }
    return Text(Duration.seconds(seconds), format: .units(allowed: [.hours, .minutes], width: width))
  }
}
