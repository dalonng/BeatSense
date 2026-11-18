import AANModels
import SwiftUI

extension TodayHealthMetric {
  var localizedTitle: LocalizedStringResource {
    switch self {
    case .heartRate: .todayHealthHeartRate
    case .bloodOxygen: .todayHealthBloodOxygen
    case .respiratoryRate: .todayHealthRespiratoryRate
    case .restingHeartRate: .todayHealthRestingHeartRate
    case .heartRateVariability: .todayHealthHeartRateVariability
    }
  }

  var titleSystemImage: String {
    switch self {
    case .heartRate: "heart.fill"
    case .bloodOxygen: "drop.fill"
    case .respiratoryRate: "lungs.fill"
    case .restingHeartRate: "heart.circle.fill"
    case .heartRateVariability: "waveform.path.ecg"
    }
  }

  var tintColor: Color {
    switch self {
    case .heartRate: .red
    case .bloodOxygen: .blue
    case .respiratoryRate: .teal
    case .restingHeartRate: .orange
    case .heartRateVariability: .purple
    }
  }
}
