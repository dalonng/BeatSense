public enum AppleHealthError: Error, Equatable {
  case unavailable
  case restricted
  case authorizationFailed
  case invalidAnchor
  case queryFailed
}
