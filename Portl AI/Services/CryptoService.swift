import Foundation

/// Service for fetching cryptocurrency market data from CoinGecko API.
/// Uses CacheManager for TTL-based caching and RateLimiter to stay within
/// the free tier limit (25 requests/minute, well under CoinGecko's 30/min cap).
actor CryptoService {

    static let shared = CryptoService()

    private let baseURL = "https://api.coingecko.com/api/v3"
    private let cache = CacheManager.shared
    private let rateLimiter = RateLimiter.shared

    /// URLSession with snappy timeouts for a responsive UI
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    // MARK: - Disk Cache

    private static let diskCacheFile: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("portl_market_cache.json")
    }()

    /// Loads cached market data from disk (survives app restarts)
    func loadDiskCache() -> [Cryptocurrency]? {
        guard let data = try? Data(contentsOf: Self.diskCacheFile) else { return nil }
        return try? JSONDecoder().decode([Cryptocurrency].self, from: data)
    }

    /// Saves market data to disk
    private func saveDiskCache(_ coins: [Cryptocurrency]) {
        if let data = try? JSONEncoder().encode(coins) {
            try? data.write(to: Self.diskCacheFile, options: .atomic)
        }
    }

    // MARK: - Core Network Helper

    /// Performs a rate-limited GET request with automatic retry on 429.
    /// Returns the raw `Data` on success.
    private func rateLimitedRequest(url: URL, maxRetries: Int = 1) async throws -> Data {
        var lastError: Error = CryptoServiceError.requestFailed

        for attempt in 0...maxRetries {
            if attempt > 0 {
                // Short backoff before retry: 1.5s
                try await Task.sleep(for: .seconds(1.5))
            }

            try Task.checkCancellation()

            // Wait for a rate limiter slot
            try await rateLimiter.acquire()

            do {
                let (data, response) = try await session.data(from: url)

                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 429 {
                        // Rate limited — retry after backoff
                        lastError = CryptoServiceError.requestFailed
                        continue
                    }
                    guard (200...299).contains(http.statusCode) else {
                        lastError = CryptoServiceError.requestFailed
                        continue
                    }
                }

                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    // MARK: - Market Data (batch endpoint)

    /// Fetches top cryptocurrencies using the batch `/coins/markets` endpoint.
    /// Returns up to `limit` coins in a single API call.
    func fetchTopCryptos(limit: Int = 30, currency: String = "usd") async throws -> [Cryptocurrency] {
        let cacheKey = CacheManager.marketKey(limit: limit, currency: currency)

        // Check in-memory cache first
        if let cached: [Cryptocurrency] = await cache.get(cacheKey) {
            return cached
        }

        let urlString = "\(baseURL)/coins/markets?vs_currency=\(currency)&order=market_cap_desc&per_page=\(limit)&page=1&sparkline=false"

        guard let url = URL(string: urlString) else {
            throw CryptoServiceError.invalidURL
        }

        do {
            let data = try await rateLimitedRequest(url: url)
            let decoded = try JSONDecoder().decode([Cryptocurrency].self, from: data)
            await cache.set(cacheKey, value: decoded, category: .marketData)
            saveDiskCache(decoded)
            return decoded
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // On failure, fall back to stale in-memory data, then disk.
            // This uses getStale, not get: get only returns unexpired entries,
            // so the old code could never reach its own fallback.
            if let stale: (value: [Cryptocurrency], age: TimeInterval) = await cache.getStale(cacheKey) {
                return stale.value
            }
            if let diskData = loadDiskCache() {
                return diskData
            }
            throw error
        }
    }

    /// Fetches sparkline data for enriching existing coins.
    func fetchWithSparklines(limit: Int = 15, currency: String = "usd") async throws -> [Cryptocurrency] {
        let urlString = "\(baseURL)/coins/markets?vs_currency=\(currency)&order=market_cap_desc&per_page=\(limit)&page=1&sparkline=true"

        guard let url = URL(string: urlString) else {
            throw CryptoServiceError.invalidURL
        }

        let data = try await rateLimitedRequest(url: url)
        return try JSONDecoder().decode([Cryptocurrency].self, from: data)
    }

    // MARK: - Single Coin Price

    /// Fetches live price for a single coin. Not cached — used for real-time
    /// polling on the detail screen. Rate limiter still applies.
    func fetchSingleCoinPrice(
        for cryptoId: String,
        currency: String = "usd"
    ) async throws -> (price: Double, change24h: Double, marketCap: Double, volume: Double, high24h: Double, low24h: Double) {
        let urlString = "\(baseURL)/simple/price?ids=\(cryptoId)&vs_currencies=\(currency)&include_24hr_change=true&include_market_cap=true&include_24hr_vol=true"

        guard let url = URL(string: urlString) else {
            throw CryptoServiceError.invalidURL
        }

        let data = try await rateLimitedRequest(url: url)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Double]]
        guard let coinData = json?[cryptoId] else {
            throw CryptoServiceError.decodingFailed
        }

        let price = coinData[currency] ?? 0
        let change = coinData["\(currency)_24h_change"] ?? 0
        let cap = coinData["\(currency)_market_cap"] ?? 0
        let vol = coinData["\(currency)_24h_vol"] ?? 0

        return (price, change, cap, vol, 0.0, 0.0)
    }

    // MARK: - Batch Prices

    func fetchBatchPrices(
        for coinIds: [String],
        currency: String = "usd"
    ) async throws -> [String: (price: Double, change24h: Double, marketCap: Double, volume: Double)] {
        guard !coinIds.isEmpty else { return [:] }

        let cacheKey = CacheManager.batchPriceKey(ids: coinIds, currency: currency)

        // Check cache
        if let cached: [String: (price: Double, change24h: Double, marketCap: Double, volume: Double)] = await cache.get(cacheKey) {
            return cached
        }

        let ids = coinIds.joined(separator: ",")
        let urlString = "\(baseURL)/simple/price?ids=\(ids)&vs_currencies=\(currency)&include_24hr_change=true&include_market_cap=true&include_24hr_vol=true"

        guard let url = URL(string: urlString) else {
            throw CryptoServiceError.invalidURL
        }

        let data = try await rateLimitedRequest(url: url)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Double]]
        guard let json else { throw CryptoServiceError.decodingFailed }

        var result: [String: (price: Double, change24h: Double, marketCap: Double, volume: Double)] = [:]
        for (coinId, coinData) in json {
            let price = coinData[currency] ?? 0
            let change = coinData["\(currency)_24h_change"] ?? 0
            let cap = coinData["\(currency)_market_cap"] ?? 0
            let vol = coinData["\(currency)_24h_vol"] ?? 0
            result[coinId] = (price, change, cap, vol)
        }

        await cache.set(cacheKey, value: result, category: .prices)
        return result
    }

    // MARK: - Chart Data

    func cachedPriceHistory(for cryptoId: String, days: String) async -> [PriceDataPoint]? {
        let cacheKey = CacheManager.chartKey(coinId: cryptoId, days: days, currency: "usd")
        return await cache.get(cacheKey)
    }

    func fetchPriceHistory(
        for cryptoId: String,
        days: String = "7",
        currency: String = "usd"
    ) async throws -> [PriceDataPoint] {
        let cacheKey = CacheManager.chartKey(coinId: cryptoId, days: days, currency: currency)

        // Check cache (3 min TTL)
        if let cached: [PriceDataPoint] = await cache.get(cacheKey) {
            return cached
        }

        let urlString = "\(baseURL)/coins/\(cryptoId)/market_chart?vs_currency=\(currency)&days=\(days)"

        guard let url = URL(string: urlString) else {
            throw CryptoServiceError.invalidURL
        }

        do {
            let data = try await rateLimitedRequest(url: url)
            let decoded = try JSONDecoder().decode(MarketChartResponse.self, from: data)

            let points = decoded.prices.map { pair in
                let timestamp = pair[0] / 1000
                let price = pair[1]
                return PriceDataPoint(date: Date(timeIntervalSince1970: timestamp), price: price)
            }

            await cache.set(cacheKey, value: points, category: .charts)
            return points
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Return stale cache if available (see note above on getStale)
            if let stale: (value: [PriceDataPoint], age: TimeInterval) = await cache.getStale(cacheKey) {
                return stale.value
            }
            throw error
        }
    }

    // MARK: - Coin Lookup

    func fetchCoinsById(ids: [String], currency: String = "usd") async throws -> [Cryptocurrency] {
        guard !ids.isEmpty else { return [] }

        let cacheKey = CacheManager.coinsByIdKey(ids: ids, currency: currency)

        if let cached: [Cryptocurrency] = await cache.get(cacheKey) {
            return cached
        }

        let joined = ids.joined(separator: ",")
        let urlString = "\(baseURL)/coins/markets?vs_currency=\(currency)&ids=\(joined)&order=market_cap_desc&sparkline=false"

        guard let url = URL(string: urlString) else {
            throw CryptoServiceError.invalidURL
        }

        let data = try await rateLimitedRequest(url: url)
        let decoded = try JSONDecoder().decode([Cryptocurrency].self, from: data)
        await cache.set(cacheKey, value: decoded, category: .marketData)
        return decoded
    }

    func searchCoins(query: String) async throws -> [CoinSearchResult] {
        guard !query.isEmpty else { return [] }

        let cacheKey = CacheManager.searchKey(query: query)

        if let cached: [CoinSearchResult] = await cache.get(cacheKey) {
            return cached
        }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(baseURL)/search?query=\(encoded)"

        guard let url = URL(string: urlString) else {
            throw CryptoServiceError.invalidURL
        }

        let data = try await rateLimitedRequest(url: url)
        let decoded = try JSONDecoder().decode(CoinSearchResponse.self, from: data)
        await cache.set(cacheKey, value: decoded.coins, category: .search)
        return decoded.coins
    }
}

// MARK: - Response Types

nonisolated private struct CoinSearchResponse: Codable, Sendable {
    let coins: [CoinSearchResult]
}

struct CoinSearchResult: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let thumb: String?
    let large: String?
    let marketCapRank: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, thumb, large
        case marketCapRank = "market_cap_rank"
    }
}

nonisolated private struct MarketChartResponse: Codable, Sendable {
    let prices: [[Double]]
}

enum CryptoServiceError: LocalizedError {
    case invalidURL
    case requestFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL for crypto API request."
        case .requestFailed:
            return "Failed to fetch data from the crypto API."
        case .decodingFailed:
            return "Failed to decode the crypto API response."
        }
    }
}
