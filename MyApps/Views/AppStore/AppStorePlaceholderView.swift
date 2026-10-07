import SwiftUI

struct AppStorePlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "App Store Connect",
            systemImage: "app.badge.checkmark",
            description: Text("Reserved for a later MyApps phase.")
        )
        .navigationTitle("App Store")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
