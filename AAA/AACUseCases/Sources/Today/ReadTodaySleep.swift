import AAMServices
import AANModels
import Foundation

struct ReadTodaySleep: Sendable {
  private struct Boundary {
    let date: Date
    let state: SleepSample.State
    let change: Int
  }

  private struct Session {
    let startDate: Date
    var endDate: Date
    var durations: [SleepSample.State: TimeInterval] = [:]
    var pendingAwake: TimeInterval = 0

    var summary: TodaySleepSummary {
      TodaySleepSummary(startDate: startDate, endDate: endDate, stageDurations: durations)
    }
  }

  /// HealthKit supplies stages without a session ID. Keep short awakenings in the same session.
  private static let maximumGap: TimeInterval = 90 * 60

  let appleHealth: any AppleHealthReading

  func callAsFunction(now: Date, calendar: Calendar) async throws -> TodaySleepSummary? {
    let todayStart = calendar.startOfDay(for: now)
    let yesterdayStart = calendar.startOfDay(for: todayStart.addingTimeInterval(-1))
    let interval = DateInterval(start: yesterdayStart, end: now)
    try Task.checkCancellation()
    let samples = try await appleHealth.sleepSamples(in: interval)
    try Task.checkCancellation()
    return Self.summary(from: samples, in: interval, wakingSince: todayStart)
  }

  private static func summary(
    from samples: [SleepSample],
    in interval: DateInterval,
    wakingSince todayStart: Date
  ) -> TodaySleepSummary? {
    var sessions: [Session] = []
    var active: [SleepSample.State: Int] = [:]
    var previous = interval.start

    for boundary in boundaries(for: samples, in: interval) {
      if boundary.date > previous, let state = resolvedState(active) {
        record(state, from: previous, to: boundary.date, in: &sessions)
      }
      active[boundary.state, default: 0] += boundary.change
      previous = boundary.date
    }

    // A later nap cannot replace a longer main sleep. Prefer the later wake time on a tie.
    return sessions.lazy.filter { $0.startDate >= interval.start && $0.endDate >= todayStart }.map(\.summary).max {
      $0.asleepDuration == $1.asleepDuration ? $0.endDate < $1.endDate : $0.asleepDuration < $1.asleepDuration
    }
  }

  private static func record(_ state: SleepSample.State, from start: Date, to end: Date, in sessions: inout [Session]) {
    let duration = end.timeIntervalSince(start)
    let last = sessions.indices.last
    if state == .awake {
      // Count this only if another sleep span later places it inside the same session.
      if let last {
        sessions[last].pendingAwake += duration
      }
      return
    }
    guard let last, start.timeIntervalSince(sessions[last].endDate) <= maximumGap else {
      sessions.append(Session(startDate: start, endDate: end, durations: [state: duration]))
      return
    }
    let awake = sessions[last].pendingAwake
    if awake > 0 {
      sessions[last].durations[.awake, default: 0] += awake
      sessions[last].pendingAwake = 0
    }
    sessions[last].durations[state, default: 0] += duration
    sessions[last].endDate = end
  }

  private static func boundaries(for samples: [SleepSample], in interval: DateInterval) -> [Boundary] {
    var boundaries: [Boundary] = []
    boundaries.reserveCapacity(2 * samples.count)
    for sample in samples {
      let start = sample.interval.start
      let end = sample.interval.end
      guard start < end, end > interval.start, end <= interval.end else { continue }
      boundaries.append(Boundary(date: start, state: sample.state, change: 1))
      boundaries.append(Boundary(date: end, state: sample.state, change: -1))
    }
    boundaries.sort { $0.date < $1.date }
    return boundaries
  }

  private static func resolvedState(_ active: [SleepSample.State: Int]) -> SleepSample.State? {
    if active[.awake, default: 0] > 0 {
      return .awake
    }
    let core = active[.core, default: 0] > 0
    let deep = active[.deep, default: 0] > 0
    let rem = active[.rem, default: 0] > 0
    switch (core, deep, rem) {
    case (true, false, false): return .core
    case (false, true, false): return .deep
    case (false, false, true): return .rem
    case (false, false, false): return active[.asleep, default: 0] > 0 ? .asleep : nil
    // Conflicting sources confirm sleep but do not establish a unique stage.
    default: return .asleep
    }
  }
}
