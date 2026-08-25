import SwiftUI

/// Manages the app's color scheme preference (light/dark mode).
/// Persists the user's choice via UserDefaults.
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    /// Whether dark mode is enabled
    var isDarkMode: Bool {
        didSet {
            UserDefaults.standard.set(isDarkMode, forKey: "isDarkMode")
        }
    }

    /// The resolved color scheme for `.preferredColorScheme()`
    var colorScheme: ColorScheme {
        isDarkMode ? .dark : .light
    }

    private init() {
        // Default to dark mode on first launch
        if UserDefaults.standard.object(forKey: "isDarkMode") == nil {
            self.isDarkMode = true
        } else {
            self.isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")
        }
    }
}
