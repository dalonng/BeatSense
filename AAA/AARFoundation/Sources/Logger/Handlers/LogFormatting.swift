import Logging

enum LogFormatting {
  static func formatPayload(_ event: LogEvent, base: Logger.Metadata, provider: Logger.MetadataProvider?) -> String {
    var merged = resolveMetadata(provider: provider, base: base, explicit: event.metadata)
    if merged["error.type"] == nil, let error = event.error {
      merged["error.type"] = .string(String(reflecting: type(of: error)))
    }

    let details = formatMetadata(merged)
    return details.isEmpty ? event.message.description : "\(event.message) | \(details)"
  }

  static func resolveMetadata(
    provider: Logger.MetadataProvider?,
    base: Logger.Metadata,
    explicit: Logger.Metadata?
  ) -> Logger.Metadata {
    var merged = provider?.get() ?? [:]
    if !base.isEmpty {
      merged.merge(base) { _, new in new }
    }
    if let explicit, !explicit.isEmpty {
      merged.merge(explicit) { _, new in new }
    }
    return merged
  }

  static func formatMetadata(_ metadata: Logger.Metadata) -> String {
    guard !metadata.isEmpty else { return "" }

    return metadata
      .sorted { $0.key < $1.key }
      .lazy
      .map { "\($0.key)=\($0.value)" }
      .joined(separator: ", ")
  }

  static func fileName(from path: String) -> Substring {
    path.split(separator: "/").last ?? Substring(path)
  }
}
