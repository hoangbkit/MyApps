import AppFoundation
import Foundation

/// MyApps exposes only the six built-in AppFoundation themes. They are all
/// permanently free: no subscription entitlement, trial, or timed preview.
enum MyAppsThemeCatalog {
    static let storageKey = "myapps.appfoundation.theme-state"
    static let legacyAppearanceStorageKey = "myapps.appearance"

    static let catalog = ThemeCatalog(
        themes: FoundationThemes.all.map { $0.withAccess(.free) },
        fallbackThemeID: FoundationThemes.rose.id
    )

    /// Interpret preferences written before AppFoundation was introduced.
    /// A saved Foundation theme takes precedence over legacy appearance.
    static func restoredThemeID(themeID: String?, legacyAppearance: String) -> String {
        if let themeID, catalog.theme(id: themeID) != nil {
            return themeID
        }
        return legacyAppearance == "Light" ? FoundationThemes.paper.id : catalog.fallbackThemeID
    }

    @MainActor
    static func makeManager() -> ThemeManager {
        let defaults = UserDefaults.standard
        // Preserve an explicit Light/Dark choice on upgrade. "System" has no
        // corresponding AppFoundation theme, so use the catalog's Rose default.
        let legacyChoice = defaults.object(forKey: storageKey) == nil
            ? defaults.string(forKey: legacyAppearanceStorageKey)
            : nil
        let manager = ThemeManager(
            catalog: catalog,
            stateStore: UserDefaultsThemeStateStore(storageKey: storageKey),
            hasPro: false,
            previewBehavior: .disabled
        )
        if let legacyChoice {
            _ = manager.select(themeID: restoredThemeID(themeID: nil, legacyAppearance: legacyChoice))
        }
        return manager
    }
}
