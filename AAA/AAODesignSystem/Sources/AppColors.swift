import SwiftUI
import UIKit

/// Semantic colors that resolve in the current system appearance.
public enum AppColors {
  public static let background = Color(uiColor: .systemBackground)
  public static let secondaryBackground = Color(uiColor: .secondarySystemBackground)

  /// Pair these for grouped pages and their content surfaces.
  public static let groupedBackground = Color(uiColor: .systemGroupedBackground)
  public static let groupedSurface = Color(uiColor: .secondarySystemGroupedBackground)

  public static let primaryText = Color.primary
  public static let secondaryText = Color.secondary
  public static let separator = Color(uiColor: .separator)

  public static let tint = Color(uiColor: .systemBlue)
  public static let link = Color(uiColor: .link)

  // Pair status colors with a label or symbol.
  public static let success = Color(uiColor: .systemGreen)
  public static let warning = Color(uiColor: .systemOrange)
  public static let error = Color(uiColor: .systemRed)
}
