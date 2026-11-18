import AAODesignSystem
import SwiftUI

public struct TodayHeartRateAbout: View {
  public init() {}

  public var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: AppSpacing.small) {
        Text(.todayHeartRateAboutBody)
          .foregroundStyle(AppColors.secondaryText)
        if let url =
          URL(string: "https://www.mayoclinic.org/healthy-lifestyle/fitness/expert-answers/heart-rate/faq-20057979")
        {
          Link(destination: url) {
            Label(.todayHeartRateAboutSource, systemImage: "arrow.up.right")
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Text(.todayHeartRateAbout)
        .accessibilityAddTraits(.isHeader)
    }
  }
}
