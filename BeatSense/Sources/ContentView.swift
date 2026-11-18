import SwiftUI

struct ContentView: View {
  var body: some View {
    TabView {
      Tab(.tabToday, systemImage: "heart.fill") {
        Color.clear
      }

      Tab(.tabTrends, systemImage: "chart.bar.fill") {
        Color.clear
      }

      Tab(.tabLongevity, systemImage: "hourglass") {
        Color.clear
      }

      Tab(.tabHealthInsights, systemImage: "text.book.closed.fill") {
        Color.clear
      }
    }
    .tint(.red)
  }
}
