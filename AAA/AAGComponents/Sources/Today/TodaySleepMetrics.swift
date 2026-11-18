import AANModels
import AAODesignSystem
import SwiftUI

public struct TodaySleepMetrics: View {
  @Environment(\.locale) private var locale
  @Environment(\.timeZone) private var timeZone

  private let summary: TodaySleepSummary

  public init(summary: TodaySleepSummary) {
    self.summary = summary
  }

  public var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: AppSpacing.small) {
        badges
      }
      .fixedSize(horizontal: true, vertical: false)
      VStack(alignment: .leading, spacing: AppSpacing.small) {
        badges
      }
    }
    .font(.subheadline.monospacedDigit())
  }

  @ViewBuilder private var badges: some View {
    let seconds = Measurement(value: summary.asleepDuration, unit: UnitDuration.seconds)
    let duration = switch seconds.value {
    case 3600...: seconds.converted(to: .hours)
    case 60...: seconds.converted(to: .minutes)
    default: seconds
    }
    let precision = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0 ... 1))
    Label {
      Text(duration, format: .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: precision))
    } icon: {
      Image(systemName: "timer")
        .foregroundStyle(.teal)
    }
    .padding(.horizontal, AppPadding.small)
    .padding(.vertical, AppPadding.tiny)
    .background(.teal.opacity(0.15), in: Capsule())
    .accessibilityLabel(Text(.todaySleepDuration))
    .accessibilityValue(Text(
      duration,
      format: .measurement(width: .wide, usage: .asProvided, numberFormatStyle: precision)
    ))

    let clock = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone)
    let start = summary.startDate.formatted(clock)
    let end = summary.endDate.formatted(clock)
    Label {
      Text(.todaySleepTimeRange(start, end))
    } icon: {
      Image(systemName: "moon.zzz.fill")
        .foregroundStyle(.indigo)
    }
    .padding(.horizontal, AppPadding.small)
    .padding(.vertical, AppPadding.tiny)
    .background(.indigo.opacity(0.15), in: Capsule())
    .accessibilityLabel(Text(.todaySleepPeriod))
    .accessibilityValue(Text(
      summary.startDate ..< summary.endDate,
      format: .interval.month(.abbreviated).day().hour().minute()
    ))
  }
}
