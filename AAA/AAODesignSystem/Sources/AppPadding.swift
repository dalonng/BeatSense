import Foundation

public enum AppSpacing {
  /// 2pt
  public static let micro: CGFloat = 2
  /// 4pt
  public static let tiny: CGFloat = 4
  /// 8pt
  public static let small: CGFloat = 8
  /// 10pt
  public static let xsmall: CGFloat = 10
  /// 12pt
  public static let medium: CGFloat = 12
  /// 16pt
  public static let regular: CGFloat = 16
  /// 20pt
  public static let xregular: CGFloat = 20
  /// 22pt
  public static let large: CGFloat = 22
  /// 24pt
  public static let xlarge: CGFloat = 24
  /// 28pt
  public static let xxlarge: CGFloat = 28
  /// 32pt
  public static let xxxlarge: CGFloat = 32
  /// 40pt
  public static let huge: CGFloat = 40
}

public enum AppPadding {
  /// 2pt
  public static let micro = AppSpacing.micro
  /// 4pt
  public static let tiny = AppSpacing.tiny
  /// 8pt
  public static let small = AppSpacing.small
  /// 10pt
  public static let xsmall = AppSpacing.xsmall
  /// 12pt
  public static let medium = AppSpacing.medium
  /// 16pt
  public static let regular = AppSpacing.regular
  /// 20pt
  public static let xregular = AppSpacing.xregular
  /// 22pt
  public static let large = AppSpacing.large
  /// 24pt
  public static let xlarge = AppSpacing.xlarge
  /// 28pt
  public static let xxlarge = AppSpacing.xxlarge
  /// 32pt
  public static let xxxlarge = AppSpacing.xxxlarge
  /// 40pt
  public static let huge = AppSpacing.huge

  // Specific paddings/sizes found in the app
  public static let headerTop: CGFloat = 22
  public static let headerBottom: CGFloat = 12
  public static let searchFieldHeight: CGFloat = 58
  public static let searchFieldBottom: CGFloat = 38
  public static let searchFieldCornerRadius: CGFloat = 10
  public static let listBottom: CGFloat = 82

  public static let avatarSize: CGFloat = 78
  public static let avatarCornerRadius: CGFloat = 8
  public static let avatarTop: CGFloat = 28

  public static let unreadDotSize: CGFloat = 20

  public static let rowTop: CGFloat = 25
  public static let rowLeading: CGFloat = 40
  public static let rowTrailing: CGFloat = 24
  public static let rowMinHeight: CGFloat = 108

  public static let tabBarTop: CGFloat = 16
  public static let tabBarBottom: CGFloat = 26
}
