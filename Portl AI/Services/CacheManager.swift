import Foundation

/// Thread-safe in-memory cache with TTL (Time-To-Live) support.
/// Each entry is tagged with a `CacheCategory` that determines how long it stays valid.
actor CacheManager {

    static let shared = CacheManager()

    // MARK: - TTL Categories

    enum CacheCategory {
        /// Live prices — 60 seconds
        case prices
        /// Market list, trending coins — 5 minutes
        case marketData
        /// Coin details, descriptions — 30 minutes
        case coinDetails
        /// Chart data — 3 minutes
        case charts
        /// Search results — 2 minutes
        case search

        var ttl: TimeInterval {
            switch self {
            case .prices:     return 60
            case .marketData: return 300
            case .coinDetails: return 1800
            case .charts:     return 180
            case .search:     return 120
            }
        }
    }

    // MARK: - Storage

    private struct CacheEntry {
        let data: Any
        let timestamp: Date
        let category: CacheCategory

        var isValid: Bool {
            Date().timeIntervalSince(timestamp) < category.ttl
        }
    }

    private var entries: [String: CacheEntry] = [:]

    // MARK: - Public API

    /// Retrieves a cached value if it exists and hasn't expired.
    ///
    /// Expired entries are RETAINED, not deleted. Deleting them here made
    /// CryptoService's "return stale cache on failure" fallback unreachable:
    /// the expiry check evicted the entry, so the catch block always found
    /// nothing. Eviction is handled by `purgeExpired()` instead.
    func get<T>(_ key: String) -> T? {
        guard let entry = entries[key], entry.isValid else { return nil }
        return entry.data as? T
    }

    /// Retrieves a value regardless of age, for use as a fallback when the
    /// network fails. Returns the value and how stale it is, so callers can
    /// tell the user they're looking at older data.
    func getStale<T>(_ key: String) -> (value: T, age: TimeInterval)? {
        guard let entry = entries[key], let value = entry.data as? T else { return nil }
        return (value, Date().timeIntervalSince(entry.timestamp))
    }

    /// Stores a value in the cache with the given category's TTL.
    func set<T>(_ key: String, value: T, category: CacheCategory) {
        entries[key] = CacheEntry(data: value, timestamp: Date(), category: category)
    }

    /// Removes a specific cache entry.
    func remove(_ key: String) {
        entries.removeValue(forKey: key)
    }

    /// Removes all entries in a specific category.
    func clearCategory(_ category: CacheCategory) {
        entries = entries.filter { $0.value.category != category }
    }

    /// Removes all expired entries (housekeeping).
    func purgeExpired() {
        entries = entries.filter { $0.value.isValid }
    }

    /// Removes everything.
    func clearAll() {
        entries.removeAll()
    }

    // MARK: - Convenience Keys

    /// Generates a cache key for market list data.
    static func marketKey(limit: Int, currency: String) -> String {
        "market_\(currency)_\(limit)"
    }

    /// Generates a cache key for batch prices.
    static func batchPriceKey(ids: [String], currency: String) -> String {
        "batch_\(currency)_\(ids.sorted().joined(separator: ","))"
    }

    /// Generates a cache key for chart data.
    static func chartKey(coinId: String, days: String, currency: String) -> String {
        "chart_\(coinId)_\(days)_\(currency)"
    }

    /// Generates a cache key for single coin price.
    static func singlePriceKey(coinId: String, currency: String) -> String {
        "price_\(coinId)_\(currency)"
    }

    /// Generates a cache key for coin search.
    static func searchKey(query: String) -> String {
        "search_\(query.lowercased())"
    }

    /// Generates a cache key for coins by ID lookup.
    static func coinsByIdKey(ids: [String], currency: String) -> String {
        "coinsById_\(currency)_\(ids.sorted().joined(separator: ","))"
    }
}
