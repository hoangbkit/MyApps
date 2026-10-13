import AppFoundation
import Foundation

/// Six built-in AppFoundation themes plus ZukaMe's signature aqua palette.
/// All themes remain permanently free, without trial or timed preview.
enum MyAppsThemeCatalog {
    static let storageKey = "myapps.appfoundation.theme-state"
    static let legacyAppearanceStorageKey = "myapps.appearance"

    /// Branded dark-aqua theme drawn from the app icon's cyan gradients.
    /// Deep teal keeps text readable; translucent cards echo the glass artwork.
    static let zukaMe = AppFoundation.AppTheme(
        id: "zukame",
        title: "ZukaMe",
        symbolName: "drop.fill",
        access: .free,
        appearance: ThemeAppearance(
            background: ThemeColor(hex: 0x07353E),
            gradientStart: ThemeColor(hex: 0x60DFE9),
            gradientEnd: ThemeColor(hex: 0x0EBACC),
            accent: ThemeColor(hex: 0x26C0D0),
            primaryForeground: .white,
            secondaryForeground: .white.withAlpha(0.76),
            surface: .white.withAlpha(0.08),
            elevatedSurface: .white.withAlpha(0.13),
            border: ThemeColor(hex: 0x60DFE9, alpha: 0.22),
            shadow: .black.withAlpha(0.32),
            preferredColorScheme: .dark
        )
    )

    static let catalog = ThemeCatalog(
        themes: [zukaMe] + FoundationThemes.all.map { $0.withAccess(.free) },
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
