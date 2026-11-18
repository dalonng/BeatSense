import Foundation

/// A transient interval of recorded sleep or wakefulness. Samples from different sources may overlap.
public struct SleepSample: Equatable, Sendable {
  public enum State: Hashable, Sendable {
    /// The source recorded sleep without identifying a specific stage.
    case asleep
    case core
    case deep
    case rem
    case awake
  }

  public let interval: DateInterval
  public let state: State

  public init(interval: DateInterval, state: State) {
    self.interval = interval
    self.state = state
  }
}
