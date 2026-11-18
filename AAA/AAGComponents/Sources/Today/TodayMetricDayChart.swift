import AANModels
import Charts
import SwiftUI

public struct TodayMetricDayChart: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.locale) private var locale
  @Environment(\.timeZone) private var timeZone
  @ScaledMetric(relativeTo: .caption) private var chartHeight = 200.0

  private let metric: TodayHealthMetric
  private let interval: DateInterval
  private let showsFullDay: Bool
  private let points: [IntradayHealthPoint]
  private let emptyLabel: LocalizedStringResource

  public init(
    metric: TodayHealthMetric,
    interval: DateInterval,
    showsFullDay: Bool,
    points: [IntradayHealthPoint],
    emptyLabel: LocalizedStringResource
  ) {
    self.metric = metric
    self.interval = interval
    self.showsFullDay = showsFullDay
    self.points = points
    self.emptyLabel = emptyLabel
  }

  public var body: some View {
    let time = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).hour()
    let ticks = axisTimes
    let labeledTicks = if dynamicTypeSize.isAccessibilitySize {
      [interval.start, ticks[ticks.count / 2], interval.end]
    } else {
      ticks
    }
    let showsMinutes = (!showsFullDay && interval.duration <= 3600)
      || ticks.contains { localCalendar.component(.minute, from: $0) != 0 }
    let axisFormat = showsMinutes ? time.minute() : time
    Chart(points.enumerated(), id: \.offset) { _, point in
      PointMark(
        x: .value(.todayDayChartTime, point.date),
        y: .value(Text(unit), axisValue(point.value))
      )
      .foregroundStyle(.tint)
      .symbolSize(24)
      .accessibilityLabel(Text(point.date, format: time.minute()))
      .accessibilityValue(TodayMetricValue.label(metric: metric, value: point.value, locale: locale, spoken: true))
    }
    .chartXScale(domain: interval.start ... interval.end)
    .chartYScale(domain: .automatic(includesZero: false, dataType: Double.self) { domain in
      // Swift Charts omits Y-axis ticks for a single value, including repeated identical readings.
      guard let first = points.first, points.allSatisfy({ $0.value == first.value }) else { return }
      let value = axisValue(first.value)
      domain.append(max(0, value - 1))
      domain.append(metric == .bloodOxygen ? min(100, value + 1) : value + 1)
    })
    .chartXAxis {
      AxisMarks(values: ticks) { mark in
        if points.isEmpty {
          AxisTick()
        } else {
          AxisGridLine()
        }
        if let date = mark.as(Date.self), labeledTicks.contains(date) {
          let anchor: UnitPoint = if date == interval.start {
            .topLeading
          } else if date == interval.end {
            .topTrailing
          } else {
            .top
          }
          AxisValueLabel(centered: false, anchor: anchor, offsetsMarks: false, horizontalSpacing: 0) {
            Text(date, format: axisFormat)
          }
        }
      }
    }
    .chartYAxis {
      if !points.isEmpty {
        AxisMarks(values: .automatic(desiredCount: 4)) {
          AxisGridLine()
          AxisValueLabel(format: FloatingPointFormatStyle<Double>(locale: locale).precision(.fractionLength(0 ... 1)))
        }
      }
    }
    .chartYAxisLabel(position: .top, alignment: .leading) {
      if !points.isEmpty {
        Text(unit)
      }
    }
    .frame(height: chartHeight)
    .accessibilityLabel(Text(.todayDayChartReadings))
    .accessibilityHidden(points.isEmpty)
    .overlay {
      if points.isEmpty {
        Text(emptyLabel)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
      }
    }
  }

  private func axisValue(_ value: Double) -> Double {
    metric == .bloodOxygen ? value * 100 : value
  }

  private var axisTimes: [Date] {
    if showsFullDay {
      let calendar = localCalendar
      let times = [6, 12, 18].compactMap {
        calendar.date(bySettingHour: $0, minute: 0, second: 0, of: interval.start)
      }
      return [interval.start] + times.filter { $0 > interval.start && $0 < interval.end } + [interval.end]
    }

    let spacing = interval.duration / 4
    return (0 ... 4).map { index in
      interval.start.addingTimeInterval(Double(index) * spacing)
    }
  }

  private var localCalendar: Calendar {
    var localCalendar = calendar
    localCalendar.timeZone = timeZone
    return localCalendar
  }

  private var unit: LocalizedStringResource {
    switch metric {
    case .heartRate, .restingHeartRate: .todayDayChartBeatsPerMinute
    case .heartRateVariability: .todayDayChartMilliseconds
    case .respiratoryRate: .todayDayChartBreathsPerMinute
    case .bloodOxygen: .todayDayChartPercent
    }
  }
}
