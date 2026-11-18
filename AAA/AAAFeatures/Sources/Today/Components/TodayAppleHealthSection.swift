import AAODesignSystem
import SwiftUI

struct TodayAppleHealthSection: View {
  let model: TodayViewModel

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: AppSpacing.medium) {
        switch model.phase {
        case .loading:
          ProgressView {
            Text(.todayHealthLoading)
          }
        case .needsConnection:
          Text(.todayHealthConnectDescription)
          Button(action: model.connect) {
            Text(.todayHealthConnect)
          }
          .buttonStyle(.borderedProminent)
        case .unavailable:
          Text(.todayHealthUnavailable)
        case .restricted:
          Text(.todayHealthRestricted)
        case .ready:
          EmptyView()
        case .failed:
          Text(.todayHealthFailed)
          Button(action: model.reload) {
            Text(.todayHealthRetry)
          }
          .buttonStyle(.bordered)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
