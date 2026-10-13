import AppFoundation
import SwiftData
import SwiftUI
import UIKit

@main
@MainActor
struct MyAppsApp: App {
    @State private var themes = MyAppsThemeCatalog.makeManager()

    private let modelContainer: ModelContainer = {
        let schema = Schema([
            ManagedApp.self,
            QuickNote.self,
            ChecklistItem.self,
            NoteAttachment.self
        ])

        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Unable to create MyApps database: \(error)")
        }
    }()

    init() {
        let navigationBar = UINavigationBar.appearance()
        navigationBar.largeTitleTextAttributes = [
            .font: Self.roundedFont(size: 34, weight: .bold)
        ]
        navigationBar.titleTextAttributes = [
            .font: Self.roundedFont(size: 17, weight: .semibold)
        ]
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(themes)
                .appFoundationTheme(themes)
        }
        .modelContainer(modelContainer)
    }

    private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}
