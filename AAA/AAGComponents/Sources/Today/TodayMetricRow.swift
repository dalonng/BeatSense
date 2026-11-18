import AAODesignSystem
import SwiftUI

public struct TodayMetricRow<Content: View>: View {
  private let title: LocalizedStringResource
  private let systemImage: String
  private let timestamp: Date?
  private let today: DateInterval?
  private let content: Content

  public init(
    title: LocalizedStringResource,
    systemImage: String,
    timestamp: Date?,
    today: DateInterval?,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.systemImage = systemImage
    self.timestamp = timestamp
    self.today = today
    self.content = content()
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.tiny) {
      TodayMetricHeader(title: title, systemImage: systemImage, timestamp: timestamp, today: today)
      content
    }
    .accessibilityElement(children: .combine)
  }
}

private struct TodayMetricHeader: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let title: LocalizedStringResource
  let systemImage: String
  let timestamp: Date?
  let today: DateInterval?

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.tiny) {
      HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
        Label {
          Text(title)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: systemImage)
            .accessibilityHidden(true)
        }
        .font(.headline)
        .foregroundStyle(.tint)
        Spacer(minLength: 0)
        if let timestamp, !dynamicTypeSize.isAccessibilitySize {
          timeLabel(timestamp)
            .multilineTextAlignment(.trailing)
            .layoutPriority(1)
        }
        Image(systemName: "chevron.forward")
          .font(.caption.weight(.semibold))
          .foregroundStyle(AppColors.secondaryText)
          .accessibilityHidden(true)
      }
      if let timestamp, dynamicTypeSize.isAccessibilitySize {
        timeLabel(timestamp)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func timeLabel(_ date: Date) -> some View {
    Text(date, format: timestampFormat(for: date))
      .font(.subheadline)
      .foregroundStyle(AppColors.secondaryText)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func timestampFormat(for date: Date) -> Date.FormatStyle {
    let time = Date.FormatStyle.dateTime.hour().minute()
    if let today, date >= today.start, date < today.end {
      return time
    }
    return time.month(.abbreviated).day()
  }
}
