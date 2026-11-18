import Foundation

/// A transient reading with the information needed to choose comparable samples.
public struct SourcedHealthSample<Sample: Sendable>: Sendable {
  public let sample: Sample
  public let sourceIdentifier: String
  public let deviceIdentifier: String?
  public let duration: TimeInterval

  public init(sample: Sample, sourceIdentifier: String, deviceIdentifier: String?, duration: TimeInterval) {
    self.sample = sample
    self.sourceIdentifier = sourceIdentifier
    self.deviceIdentifier = deviceIdentifier
    self.duration = duration
  }
}
