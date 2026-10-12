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
        let defaults = UserDefaults.standard
        let storageKey = "myapps.appfoundation.theme-state"
        // Preserve an explicit Light/Dark choice on upgrade. "System" has no
        // corresponding AppFoundation theme, so use the catalog's Rose default.
        let legacyChoice = defaults.object(forKey: storageKey) == nil
            ? defaults.string(forKey: "myapps.appearance")
            : nil
        let manager = ThemeManager(
            catalog: catalog,
            stateStore: UserDefaultsThemeStateStore(storageKey: storageKey),
            hasPro: false,
            previewBehavior: .disabled
        )
        switch legacyChoice {
        case "Light":
            _ = manager.select(themeID: FoundationThemes.paper.id)
        case "Dark":
            _ = manager.select(themeID: FoundationThemes.rose.id)
        default:
            break
        }
        return manager
    }
}
