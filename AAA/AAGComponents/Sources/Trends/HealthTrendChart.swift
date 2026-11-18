import AANModels
import AAODesignSystem
import Charts
import SwiftUI

public struct HealthTrendChart: View {
  public struct Baseline {
    let range: HealthBaselineRange
    let medianLabel: LocalizedStringResource
    let usualRangeLabel: LocalizedStringResource

    public init(
      range: HealthBaselineRange,
      medianLabel: LocalizedStringResource,
      usualRangeLabel: LocalizedStringResource
    ) {
      self.range = range
      self.medianLabel = medianLabel
      self.usualRangeLabel = usualRangeLabel
    }
  }

  private struct Point: Identifiable {
    let reading: DailyHealthValue
    let segment: Int

    var id: Date {
      reading.day
    }
  }

  @Environment(\.locale) private var locale
  @ScaledMetric(relativeTo: .caption) private var chartHeight = 144.0
  @State private var selectedDay: Date?

  private let metric: TodayHealthMetric
  private let title: LocalizedStringResource
  private let noReadingLabel: LocalizedStringResource
  private let readings: [DailyHealthValue]
  private let interval: DateInterval
  private let calendar: Calendar
  private let baseline: Baseline?

  public init(
    metric: TodayHealthMetric,
    title: LocalizedStringResource,
    noReadingLabel: LocalizedStringResource,
    readings: [DailyHealthValue],
    interval: DateInterval,
    calendar: Calendar,
    baseline: Baseline?
  ) {
    self.metric = metric
    self.title = title
    self.noReadingLabel = noReadingLabel
    self.readings = readings
    self.interval = interval
    self.calendar = calendar
    self.baseline = baseline
  }

  public var body: some View {
    let selection = selectedDay.flatMap { interval.start <= $0 && $0 < interval.end ? $0 : nil }
    let reading = if let selection {
      readings.first { $0.day == selection }
    } else {
      readings.last
    }
    if let date = selection ?? reading?.day {
      VStack(alignment: .leading, spacing: AppSpacing.tiny) {
        if let reading {
          TodayMetricValue(metric: metric, value: reading.value, style: .prominent)
        } else {
          Text(noReadingLabel)
            .font(.title2.weight(.semibold))
        }
        Text(date, format: dateFormat)
          .font(.caption)
          .foregroundStyle(AppColors.secondaryText)
      }
      .accessibilityElement(children: .combine)
    }

    Chart {
      if let baseline {
        RectangleMark(
          yStart: .value(Text(baseline.usualRangeLabel), baseline.range.lowerBound),
          yEnd: .value(Text(baseline.usualRangeLabel), baseline.range.upperBound)
        )
        .foregroundStyle(.tint.opacity(HealthTrendBaselineLegend.rangeOpacity))
        .accessibilityHidden(true)
        RuleMark(y: .value(Text(baseline.medianLabel), baseline.range.median))
          .foregroundStyle(AppColors.secondaryText)
          .lineStyle(HealthTrendBaselineLegend.medianStroke)
          .accessibilityHidden(true)
      }

      ForEach(points) { point in
        let day = PlottableValue.value(.trendsChartDate, point.reading.day, unit: .day, calendar: calendar)
        let value = PlottableValue.value(Text(title), point.reading.value)
        if metric != .heartRateVariability {
          LineMark(x: day, y: value, series: .value(Text(title), point.segment))
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
        }
        PointMark(x: day, y: value)
          .foregroundStyle(.tint)
          .symbolSize(18)
          .accessibilityLabel(Text(point.reading.day, format: dateFormat))
          .accessibilityValue(TodayMetricValue.label(
            metric: metric,
            value: point.reading.value,
            locale: locale,
            spoken: true
          ))
      }

      if let selection {
        RuleMark(x: .value(.trendsChartDate, selection, unit: .day, calendar: calendar))
          .foregroundStyle(AppColors.secondaryText)
          .accessibilityHidden(true)
      }
    }
    .chartXScale(domain: interval.start ... interval.end)
    .chartYScale(domain: .automatic(includesZero: false))
    .chartXAxis {
      AxisMarks(values: axisDays) { mark in
        let anchor: UnitPoint = if mark.index == 0 {
          .topLeading
        } else if mark.index == mark.count - 1 {
          .topTrailing
        } else {
          .top
        }
        AxisGridLine()
        AxisValueLabel(format: dateFormat, anchor: anchor)
      }
    }
    .chartYAxis {
      AxisMarks(values: .automatic(desiredCount: 3)) {
        AxisGridLine()
        if metric == .bloodOxygen {
          AxisValueLabel(format: FloatingPointFormatStyle<Double>.Percent(locale: locale)
            .precision(.fractionLength(0 ... 1)))
        } else {
          AxisValueLabel()
        }
      }
    }
    .chartOverlay { proxy in
      GeometryReader { geometry in
        Rectangle()
          .fill(.clear)
          .contentShape(.rect)
          .onTapGesture { location in
            guard let frame = proxy.plotFrame else { return }
            let plot = geometry[frame]
            guard plot.contains(location), let date: Date = proxy.value(atX: location.x - plot.minX) else { return }
            let day = calendar.startOfDay(for: date)
            selectedDay = selectedDay == day ? nil : day
          }
          .accessibilityHidden(true)
      }
    }
    .environment(\.calendar, calendar)
    .environment(\.timeZone, calendar.timeZone)
    .frame(height: chartHeight)
    .accessibilityLabel(Text(title))

    if let baseline {
      HealthTrendBaselineLegend(metric: metric, baseline: baseline)
    }
  }

  private var dateFormat: Date.FormatStyle {
    Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
  }

  private var axisDays: [Date] {
    [
      interval.start,
      calendar.startOfDay(for: interval.start + interval.duration / 2),
      calendar.startOfDay(for: interval.end - 1),
    ]
  }

  private var points: [Point] {
    var previousDay: Date?
    var segment = 0
    return readings.map { reading in
      if let previousDay, calendar.dateInterval(of: .day, for: previousDay)?.end != reading.day {
        segment += 1
      }
      previousDay = reading.day
      return Point(reading: reading, segment: segment)
    }
  }
}
