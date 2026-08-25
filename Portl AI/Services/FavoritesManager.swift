import Foundation

/// Manages the set of favorited coin IDs, persisted to UserDefaults.
/// Used by SearchView to toggle favorites and DashboardView to show them.
@MainActor @Observable
final class FavoritesManager {

    static let shared = FavoritesManager()

    private(set) var favoriteIds: Set<String>

    private let key = "favoritedCoinIds"

    private init() {
        let stored = UserDefaults.standard.stringArray(forKey: key) ?? []
        favoriteIds = Set(stored)
        // Migrate old per-coin keys (favorite_{id}) if the new key is empty
        if favoriteIds.isEmpty {
            migrateOldFavorites()
        }
    }

    func isFavorited(_ coinId: String) -> Bool {
        favoriteIds.contains(coinId)
    }

    func toggle(_ coinId: String) {
        if favoriteIds.contains(coinId) {
            favoriteIds.remove(coinId)
        } else {
            favoriteIds.insert(coinId)
        }
        save()
    }

    func add(_ coinId: String) {
        favoriteIds.insert(coinId)
        save()
    }

    func remove(_ coinId: String) {
        favoriteIds.remove(coinId)
        save()
    }

    private func save() {
        UserDefaults.standard.set(Array(favoriteIds), forKey: key)
        UserDefaults.standard.synchronize()
    }

    /// One-time migration from old per-coin UserDefaults keys
    private func migrateOldFavorites() {
        let defaults = UserDefaults.standard
        // Check known common coins and any existing favorite_ keys
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix("favorite_") {
            if defaults.bool(forKey: key) {
                let coinId = String(key.dropFirst("favorite_".count))
                favoriteIds.insert(coinId)
            }
        }
        if !favoriteIds.isEmpty {
            save()
        }
    }
}
