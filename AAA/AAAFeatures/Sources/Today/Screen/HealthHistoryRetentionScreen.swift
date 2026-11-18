import AACUseCases
import SwiftUI

struct HealthHistoryRetentionScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Binding private var retentionDays: Int
  @State private var daysText: String

  init(retentionDays: Binding<Int>) {
    _retentionDays = retentionDays
    _daysText = State(initialValue: String(retentionDays.wrappedValue))
  }

  private var validDays: Int? {
    guard let days = Int(daysText), SynchronizeHealthHistory.isValidRetention(days) else { return nil }
    return days
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(text: $daysText, prompt: Text(.healthHistoryRetentionDays)) {
            Text(.healthHistoryRetentionDays)
          }
          .keyboardType(.numberPad)
          .accessibilityLabel(Text(.healthHistoryRetentionDays))
        } header: {
          Text(.healthHistoryRetentionDays)
        } footer: {
          Text(.healthHistoryRetentionDescription)
        }
      }
      .navigationTitle(Text(.healthHistoryRetentionHeading))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(role: .cancel) { dismiss() } label: { Text(.healthHistoryRetentionCancel) }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            guard let validDays else { return }
            retentionDays = validDays
            dismiss()
          } label: {
            Text(.healthHistoryRetentionSave)
          }
          .disabled(validDays == nil)
        }
      }
    }
  }
}
