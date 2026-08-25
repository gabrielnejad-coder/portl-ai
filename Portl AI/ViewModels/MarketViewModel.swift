import Foundation

/// View model for the market dashboard.
/// Lazy loads data: disk cache → market list → sparklines (deferred).
@MainActor @Observable
final class MarketViewModel {

    var cryptocurrencies: [Cryptocurrency] = []
    var isLoading = false
    var errorMessage: String?

    private let cryptoService = CryptoService.shared
    private var pollingTask: Task<Void, Never>?
    private var sparklineTask: Task<Void, Never>?

    // MARK: - Primary Load

    func loadMarketData() async {
        let wasEmpty = cryptocurrencies.isEmpty
        isLoading = wasEmpty
        errorMessage = nil

        // Step 0: Show disk cache instantly if we have nothing displayed
        if wasEmpty, let cached = await cryptoService.loadDiskCache() {
            cryptocurrencies = cached
            isLoading = false
        }

        // Step 1: Fetch fresh market list (single batch call)
        do {
            try Task.checkCancellation()
            let cryptos = try await cryptoService.fetchTopCryptos(limit: 30)
            let topIds = Set(cryptos.map(\.id))

            // Preserve any extra coins (favorited/wallet) that aren't in the top list
            let extras = cryptocurrencies.filter { !topIds.contains($0.id) }
            cryptocurrencies = cryptos + extras

            errorMessage = nil
        } catch is CancellationError {
            // View disappeared — don't set error
            isLoading = false
            return
        } catch {
            if cryptocurrencies.isEmpty {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    // MARK: - Deferred Sparkline Loading

    /// Call this after initial data is visible. Waits 15 seconds then fetches sparklines.
    func loadSparklinesIfNeeded() {
        sparklineTask?.cancel()
        sparklineTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(15))
                try Task.checkCancellation()
                guard let self else { return }
                let enriched = try await self.cryptoService.fetchWithSparklines(limit: 15)
                for i in self.cryptocurrencies.indices {
                    if let match = enriched.first(where: { $0.id == self.cryptocurrencies[i].id }) {
                        self.cryptocurrencies[i].sparklineIn7d = match.sparklineIn7d
                        self.cryptocurrencies[i].currentPrice = match.currentPrice
                        self.cryptocurrencies[i].priceChangePercentage24h = match.priceChangePercentage24h
                    }
                }
            } catch {
                // Sparklines are optional — ignore errors
            }
        }
    }

    // MARK: - Polling

    /// Starts periodic polling (every 120 seconds to stay well within rate limits)
    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { break }
                await self?.refreshPrices()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        sparklineTask?.cancel()
        sparklineTask = nil
    }

    /// Lightweight price refresh using batch endpoint (single API call for all coins)
    private func refreshPrices() async {
        guard !cryptocurrencies.isEmpty else { return }
        do {
            let ids = cryptocurrencies.map(\.id)
            let prices = try await cryptoService.fetchBatchPrices(for: ids)
            for i in cryptocurrencies.indices {
                let id = cryptocurrencies[i].id
                if let updated = prices[id] {
                    cryptocurrencies[i].currentPrice = updated.price
                    cryptocurrencies[i].priceChangePercentage24h = updated.change24h
                    cryptocurrencies[i].marketCap = updated.marketCap
                    cryptocurrencies[i].totalVolume = updated.volume
                }
            }
        } catch {
            // Silently fail — next poll will retry
        }
    }

    // MARK: - Favorited Coins

    /// Loads market data for favorited coins not already in the main list.
    /// Batches requests to avoid overly long URLs.
    func loadFavoritedCoins(_ favoritedIds: Set<String>) async {
        let existingIds = Set(cryptocurrencies.map(\.id))
        let missing = Array(favoritedIds.subtracting(existingIds))
        guard !missing.isEmpty else { return }

        // Batch into groups of 25 to keep URL length reasonable
        let batchSize = 25
        for batch in stride(from: 0, to: missing.count, by: batchSize) {
            let end = min(batch + batchSize, missing.count)
            let ids = Array(missing[batch..<end])
            do {
                let extra = try await cryptoService.fetchCoinsById(ids: ids)
                cryptocurrencies.append(contentsOf: extra)
            } catch {
                // Continue with next batch even if one fails
            }
        }
    }

    func refresh() async {
        await loadMarketData()
        await loadFavoritedCoins(FavoritesManager.shared.favoriteIds)
    }
}
