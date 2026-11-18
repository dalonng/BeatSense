import AANModels
import AAODesignSystem
import SwiftUI

struct HealthTrendBaselineLegend: View {
  static let rangeOpacity = 0.14
  static let medianStroke = StrokeStyle(lineWidth: 1.5, dash: [4, 3])

  @Environment(\.locale) private var locale

  let metric: TodayHealthMetric
  let baseline: HealthTrendChart.Baseline

  var body: some View {
    VStack(alignment: .leading, spacing: AppSpacing.tiny) {
      HStack(spacing: AppSpacing.small) {
        Path { path in
          path.move(to: CGPoint(x: 0, y: 4))
          path.addLine(to: CGPoint(x: 16, y: 4))
        }
        .stroke(style: Self.medianStroke)
        .frame(width: 16, height: 8)
        .accessibilityHidden(true)
        Text(baseline.medianLabel)
        TodayMetricValue.label(metric: metric, value: baseline.range.median, locale: locale)
          .accessibilityLabel(TodayMetricValue.label(
            metric: metric, value: baseline.range.median, locale: locale, spoken: true
          ))
      }
      .accessibilityElement(children: .combine)

      HStack(spacing: AppSpacing.small) {
        RoundedRectangle(cornerRadius: 2)
          .fill(.tint.opacity(Self.rangeOpacity))
          .frame(width: 16, height: 8)
          .accessibilityHidden(true)
        Text(baseline.usualRangeLabel)
        Text(verbatim: formattedRange)
      }
      .accessibilityElement(children: .combine)
    }
    .font(.caption)
    .monospacedDigit()
    .foregroundStyle(AppColors.secondaryText)
  }

  private var formattedRange: String {
    let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0 ... 1)).locale(locale)
    let lower = baseline.range.lowerBound.formatted(style)
    let upper = baseline.range.upperBound.formatted(style)
    return lower == upper ? lower : "\(lower)–\(upper)"
  }
}
