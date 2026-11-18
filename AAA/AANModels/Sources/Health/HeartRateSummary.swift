/// Aggregates the visible heart rate measurements in a requested interval.
public struct HeartRateSummary: Equatable, Sendable {
  /// Counts measurements in a BPM range with an inclusive lower bound and an exclusive upper bound.
  public struct Bucket: Equatable, Sendable {
    public let lowerBoundBPM: Int
    /// A missing upper bound represents an open-ended range.
    public let upperBoundBPM: Int?
    public let count: Int

    public init(lowerBoundBPM: Int, upperBoundBPM: Int?, count: Int) {
      self.lowerBoundBPM = lowerBoundBPM
      self.upperBoundBPM = upperBoundBPM
      self.count = count
    }
  }

  public let latest: HeartRateSample
  /// The arithmetic mean of the visible measurements, in BPM.
  public let averageBPM: Double
  public let minimumBPM: Double
  public let maximumBPM: Double
  /// Counts measurement entries rather than the time spent in each range.
  public let buckets: [Bucket]

  public var sampleCount: Int {
    buckets.reduce(0) { $0 + $1.count }
  }

  public init(
    latest: HeartRateSample,
    averageBPM: Double,
    minimumBPM: Double,
    maximumBPM: Double,
    buckets: [Bucket]
  ) {
    self.latest = latest
    self.averageBPM = averageBPM
    self.minimumBPM = minimumBPM
    self.maximumBPM = maximumBPM
    self.buckets = buckets
  }
}
