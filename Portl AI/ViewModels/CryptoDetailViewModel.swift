import Foundation

/// Time range options for the price chart
enum ChartTimeRange: String, CaseIterable, Identifiable {
    case oneHour = "1H"
    case fourHour = "4H"
    case oneDay = "1D"
    case sevenDay = "7D"
    case sixMonth = "6M"
    case all = "ALL"

    var id: String { rawValue }

    /// Days parameter for CoinGecko market_chart API (supports "max" for ALL)
    var daysParam: String {
        switch self {
        case .oneHour: return "1"
        case .fourHour: return "1"
        case .oneDay: return "1"
        case .sevenDay: return "7"
        case .sixMonth: return "180"
        case .all: return "max"
        }
    }

    /// Label for the change description
    var changeLabel: String {
        switch self {
        case .oneHour: return "Past hour"
        case .fourHour: return "Past 4 hours"
        case .oneDay: return "Past day"
        case .sevenDay: return "Past week"
        case .sixMonth: return "Past 6 months"
        case .all: return "All time"
        }
    }

    /// Target number of chart points — balanced for visual quality and drag performance.
    /// Swift Charts re-renders all marks on every state change, so fewer points = smoother crosshair.
    var targetPoints: Int {
        switch self {
        case .oneHour: return 100
        case .fourHour: return 120
        case .oneDay: return 150
        case .sevenDay: return 150
        case .sixMonth: return 180
        case .all: return 180
        }
    }

    /// Time window cutoff — filters data to this range's visible window
    var cutoff: Date? {
        let now = Date()
        switch self {
        case .oneHour: return now.addingTimeInterval(-3600)
        case .fourHour: return now.addingTimeInterval(-4 * 3600)
        case .oneDay, .sevenDay, .sixMonth, .all: return nil
        }
    }
}

/// View model for the crypto detail screen with live price updates
@MainActor @Observable
final class CryptoDetailViewModel {

    var crypto: Cryptocurrency
    var priceHistory: [PriceDataPoint] = [] {
        didSet { rebuildFilteredHistory() }
    }
    /// High-frequency tick data collected by polling
    private var tickHistory: [PriceDataPoint] = [] {
        didSet { rebuildFilteredHistory() }
    }
    var selectedRange: ChartTimeRange = .oneDay {
        didSet { rebuildFilteredHistory() }
    }
    var isLoadingChart = false
    var chartLoadFailed = false
    var isFavorited = false
    /// True when the crypto was created as a placeholder (price = 0) and real data hasn't loaded yet
    var isLoadingPrice = false

    /// Related news articles for this crypto
    var relatedNews: [NewsArticle] = []

    /// The point currently being inspected via drag gesture (nil when not dragging)
    var inspectedPoint: PriceDataPoint?

    /// Pre-computed chart data — updated only when source data or range changes
    private(set) var filteredHistory: [PriceDataPoint] = []

    /// Rebuilds filteredHistory from source data (called on data/range changes, not on every frame)
    private func rebuildFilteredHistory() {
        var merged = mergedHistory
        // Apply time window filter for sub-day ranges (1H, 4H share the same 1-day API data)
        if let cutoff = selectedRange.cutoff {
            merged = merged.filter { $0.date >= cutoff }
        }
        let trimmed = removeOutliers(merged)
        let result = downsample(trimmed, target: selectedRange.targetPoints)
        // Keep old data visible while switching ranges (avoids flash to "no data")
        if !result.isEmpty || filteredHistory.isEmpty {
            filteredHistory = result
        }
    }

    /// Combines API data with tick data, sorted and deduplicated
    private var mergedHistory: [PriceDataPoint] {
        var all = priceHistory + tickHistory
        all.sort { $0.date < $1.date }
        var result: [PriceDataPoint] = []
        for point in all {
            if let last = result.last,
               abs(point.date.timeIntervalSince(last.date)) < 3 {
                continue
            }
            result.append(point)
        }
        return result
    }

    /// Points relevant for calculating the price change (time-windowed for 1H/4H)
    private var changePoints: [PriceDataPoint] {
        let merged = mergedHistory
        if let cutoff = selectedRange.cutoff {
            return merged.filter { $0.date >= cutoff }
        }
        return merged
    }

    /// Percentage change for the visible range
    var rangeChangePercent: Double? {
        let points = changePoints
        guard let first = points.first?.price, first > 0,
              let last = points.last?.price else { return nil }
        return ((last - first) / first) * 100
    }

    /// Dollar change for the visible range
    var rangeChangeDollars: Double? {
        let points = changePoints
        guard let first = points.first?.price,
              let last = points.last?.price else { return nil }
        return last - first
    }

    /// The price to display — inspected point price or live price
    var displayPrice: Double {
        inspectedPoint?.price ?? crypto.currentPrice
    }

    private let service = CryptoService.shared
    private let newsService = NewsService.shared
    private var pollingTask: Task<Void, Never>?

    /// Polling interval — 30 seconds for live price updates.
    /// Rate limiter enforces 25 req/min across the app.
    private let pollingInterval: TimeInterval = 30

    init(crypto: Cryptocurrency) {
        self.crypto = crypto
        self.isLoadingPrice = crypto.currentPrice == 0
        loadFavoriteState()
    }

    // MARK: - Chart Data

    /// Attempts to pre-populate chart from cache so no spinner is shown
    func loadFromCacheIfAvailable() async {
        if let cached = await service.cachedPriceHistory(for: crypto.id, days: selectedRange.daysParam),
           !cached.isEmpty {
            priceHistory = cached
        }
    }

    func loadChart() async {
        chartLoadFailed = false
        // Show loading spinner only if we have no data at all
        if filteredHistory.isEmpty {
            // Try cache first before showing spinner
            await loadFromCacheIfAvailable()
            if filteredHistory.isEmpty {
                isLoadingChart = true
            }
        }
        do {
            // Wrap in a timeout so the user isn't stuck with a spinner
            let newData = try await withThrowingTimeout(seconds: 20) {
                try await self.service.fetchPriceHistory(
                    for: self.crypto.id,
                    days: self.selectedRange.daysParam
                )
            }
            if newData.isEmpty {
                chartLoadFailed = filteredHistory.isEmpty
            } else {
                priceHistory = newData
            }
        } catch is CancellationError {
            // View disappeared — don't mark as failed
        } catch {
            // Mark as failed only if we have no existing data to show
            if filteredHistory.isEmpty {
                chartLoadFailed = true
            }
        }
        isLoadingChart = false
    }

    /// Runs an async closure with a timeout. Throws CancellationError on timeout.
    private func withThrowingTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CancellationError()
            }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Related News

    func loadRelatedNews() async {
        do {
            relatedNews = try await newsService.fetchCryptoNews(
                symbol: crypto.symbol
            )
        } catch {
            // Non-critical — leave empty
        }
    }

    // MARK: - Live Price Polling

    /// Polls using lightweight single-coin endpoint every 30s.
    /// CacheManager with 60s TTL means actual network calls happen at most every 60s.
    func startLiveUpdates() {
        // If a Live Activity is running for this coin, stop background polling
        // since the view's own polling will take over
        if LiveActivityManager.shared.isTrackingCoin(crypto.id) {
            LiveActivityManager.shared.stopBackgroundPolling()
        }

        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            // Fetch price immediately (important for placeholder coins from search)
            await self.refreshPrice()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.pollingInterval))
                guard !Task.isCancelled else { break }
                await self.refreshPrice()
            }
        }
    }

    func stopLiveUpdates() {
        pollingTask?.cancel()
        pollingTask = nil

        // If a Live Activity is still running for this coin,
        // start background polling to keep the Dynamic Island updated
        if LiveActivityManager.shared.isTrackingCoin(crypto.id) {
            LiveActivityManager.shared.startBackgroundPolling()
        }
    }

    /// Restarts the timer with the correct interval for the current range
    func restartPollingIfNeeded() {
        stopLiveUpdates()
        startLiveUpdates()
    }

    private func refreshPrice() async {
        do {
            let result = try await service.fetchSingleCoinPrice(for: crypto.id)
            crypto.currentPrice = result.price
            crypto.priceChangePercentage24h = result.change24h
            crypto.marketCap = result.marketCap
            crypto.totalVolume = result.volume
            crypto.high24h = result.high24h
            crypto.low24h = result.low24h
            isLoadingPrice = false

            // Add tick to history
            let newPoint = PriceDataPoint(date: Date(), price: result.price)
            tickHistory.append(newPoint)

            // Prune old ticks beyond 5 hours to limit memory
            let cutoff = Date().addingTimeInterval(-5 * 3600)
            tickHistory.removeAll { $0.date < cutoff }

            // Push update to Live Activity if tracking this coin
            if LiveActivityManager.shared.isTrackingCoin(crypto.id) {
                LiveActivityManager.shared.updateTracking(
                    price: result.price,
                    change24h: result.change24h,
                    high24h: result.high24h,
                    low24h: result.low24h
                )
            }
        } catch {
            // Silently fail — next tick will retry
        }
    }

    // MARK: - Data Cleaning

    /// Removes price outlier points that cause the chart to compress.
    /// Uses a wider tolerance for small-value coins where price swings are proportionally larger.
    private func removeOutliers(_ points: [PriceDataPoint]) -> [PriceDataPoint] {
        guard points.count >= 4 else { return points }

        let prices = points.map(\.price).sorted()
        let q1 = prices[prices.count / 4]
        let q3 = prices[3 * prices.count / 4]
        let iqr = q3 - q1

        // For very small IQR (low-value coins with tight ranges), skip outlier removal
        // to preserve meaningful price detail
        let median = prices[prices.count / 2]
        if median > 0 && iqr / median < 0.001 {
            return points
        }

        let lowerBound = q1 - 3.0 * iqr
        let upperBound = q3 + 3.0 * iqr

        return points.filter { $0.price >= lowerBound && $0.price <= upperBound }
    }

    // MARK: - Downsampling

    /// Downsamples using LTTB (Largest Triangle Three Buckets) algorithm.
    /// Preserves visual peaks and valleys better than simple averaging,
    /// which is important for small-value coins with tight price ranges.
    private func downsample(_ points: [PriceDataPoint], target: Int) -> [PriceDataPoint] {
        guard points.count > target, target >= 2 else { return points }

        var result: [PriceDataPoint] = []
        result.reserveCapacity(target)

        // Always keep the first point
        result.append(points[0])

        let bucketSize = Double(points.count - 2) / Double(target - 2)

        for i in 0..<(target - 2) {
            let bucketStart = Int(Double(i) * bucketSize) + 1
            let bucketEnd = min(Int(Double(i + 1) * bucketSize) + 1, points.count)

            // Next bucket average (used as the "target" triangle vertex)
            let nextStart = min(Int(Double(i + 1) * bucketSize) + 1, points.count - 1)
            let nextEnd = min(Int(Double(i + 2) * bucketSize) + 1, points.count)
            let nextSlice = points[nextStart..<nextEnd]
            let avgDate = nextSlice.map { $0.date.timeIntervalSince1970 }.reduce(0, +) / Double(nextSlice.count)
            let avgPrice = nextSlice.map(\.price).reduce(0, +) / Double(nextSlice.count)

            // Pick the point in this bucket that creates the largest triangle
            let prev = result.last!
            var maxArea: Double = -1
            var bestIndex = bucketStart

            for j in bucketStart..<bucketEnd {
                let area = abs(
                    (prev.date.timeIntervalSince1970 - avgDate) * (points[j].price - prev.price) -
                    (prev.date.timeIntervalSince1970 - points[j].date.timeIntervalSince1970) * (avgPrice - prev.price)
                )
                if area > maxArea {
                    maxArea = area
                    bestIndex = j
                }
            }

            result.append(points[bestIndex])
        }

        // Always keep the last point
        result.append(points[points.count - 1])

        return result
    }

    // MARK: - Favorites

    private let favoritesManager = FavoritesManager.shared

    func toggleFavorite() {
        favoritesManager.toggle(crypto.id)
        isFavorited = favoritesManager.isFavorited(crypto.id)
    }

    private func loadFavoriteState() {
        isFavorited = favoritesManager.isFavorited(crypto.id)
    }
}
