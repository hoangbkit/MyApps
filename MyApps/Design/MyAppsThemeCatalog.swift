import AppFoundation
import Foundation

/// MyApps exposes only the six built-in AppFoundation themes. They are all
/// permanently free: no subscription entitlement, trial, or timed preview.
enum MyAppsThemeCatalog {
    static let catalog = ThemeCatalog(
        themes: FoundationThemes.all.map { $0.withAccess(.free) },
        fallbackThemeID: FoundationThemes.rose.id
    )

    @MainActor
    static func makeManager() -> ThemeManager {
        ThemeManager(
            catalog: catalog,
            stateStore: UserDefaultsThemeStateStore(storageKey: "myapps.appfoundation.theme-state"),
            hasPro: false,
            previewBehavior: .disabled
        )
    }
}
