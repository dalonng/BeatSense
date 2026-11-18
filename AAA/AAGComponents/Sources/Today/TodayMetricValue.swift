import AANModels
import SwiftUI

public struct TodayMetricValue: View {
  public enum Style {
    case uniform
    case prominent
    case statistic
  }

  @Environment(\.locale) private var locale

  private let metric: TodayHealthMetric
  private let value: Double
  private let style: Style

  public init(metric: TodayHealthMetric, value: Double, style: Style = .uniform) {
    self.metric = metric
    self.value = value
    self.style = style
  }

  public var body: some View {
    let fonts = fonts
    let label = if let unitFont = fonts.unit {
      labelWithSmallUnit(unitFont)
    } else {
      Self.label(metric: metric, value: value, locale: locale)
    }
    label
      .font(fonts.number.weight(.semibold).monospacedDigit())
      .accessibilityLabel(Self.label(metric: metric, value: value, locale: locale, spoken: true))
  }

  public static func label(metric: TodayHealthMetric, value: Double, locale: Locale, spoken: Bool = false) -> Text {
    if let resource = labelResource(metric: metric, value: value, locale: locale, spoken: spoken) {
      return Text(resource)
    }
    return Text(verbatim: value.formatted(percentStyle(locale: locale)))
  }

  private var fonts: (number: Font, unit: Font?) {
    switch style {
    case .uniform: (.title2, nil)
    case .prominent: (.title, .subheadline)
    case .statistic: (.subheadline, .caption)
    }
  }

  private func labelWithSmallUnit(_ unitFont: Font) -> Text {
    if var resource = Self.labelResource(metric: metric, value: value, locale: locale, spoken: false) {
      resource.locale = locale
      var options = AttributedString.LocalizationOptions()
      options.applyReplacementIndexAttribute = true
      var formatted = AttributedString(localized: resource, options: options)
      for (index, range) in formatted.runs[\.replacementIndex] where index == nil {
        formatted[range].swiftUI.font = unitFont
      }
      return Text(formatted)
    }

    var formatted = value.formatted(Self.percentStyle(locale: locale).attributed)
    for (symbol, range) in formatted.runs[\.numberSymbol] where symbol == .percent {
      formatted[range].swiftUI.font = unitFont
    }
    return Text(formatted)
  }

  private static func percentStyle(locale: Locale) -> FloatingPointFormatStyle<Double>.Percent {
    .init(locale: locale).precision(.fractionLength(0 ... 1))
  }

  private static func labelResource(
    metric: TodayHealthMetric,
    value: Double,
    locale: Locale,
    spoken: Bool
  ) -> LocalizedStringResource? {
    let number = value.formatted(.number.precision(.fractionLength(0 ... 1)).locale(locale))
    switch metric {
    case .heartRate, .restingHeartRate:
      return spoken ? .todayHeartRateSpokenValue(number) : .todayHeartRateValue(number)
    case .respiratoryRate:
      return spoken ? .todayHealthRespiratoryRateSpokenValue(number) : .todayHealthRespiratoryRateValue(number)
    case .heartRateVariability:
      return spoken ? .todayHealthHeartRateVariabilitySpokenValue(number) :
        .todayHealthHeartRateVariabilityValue(number)
    case .bloodOxygen:
      return nil
    }
  }
}
