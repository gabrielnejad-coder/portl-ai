import ActivityKit
import Foundation

/// Manages a single Live Activity for real-time crypto price tracking.
/// Handles starting, updating, stopping, and background polling when the detail view is dismissed.
@MainActor @Observable
final class LiveActivityManager {

    static let shared = LiveActivityManager()

    // MARK: - State

    /// The coin ID currently being tracked (nil if no activity is active)
    private(set) var trackedCoinId: String?

    /// Whether a Live Activity is currently running
    var isTracking: Bool { trackedCoinId != nil }

    private var currentActivity: Activity<CryptoLiveActivityAttributes>?
    private var backgroundPollingTask: Task<Void, Never>?

    /// Portfolio balance Dynamic Island activity
    private var portfolioActivity: Activity<PortfolioLiveActivityAttributes>?

    private let service = CryptoService.shared
    private let pollingInterval: TimeInterval = 30

    /// Cached high/low values (simple/price endpoint doesn't return these)
    private var cachedHigh24h: Double = 0
    private var cachedLow24h: Double = 0

    private init() {}

    // MARK: - Public API

    /// Returns true if this specific coin is being tracked
    func isTrackingCoin(_ coinId: String) -> Bool {
        trackedCoinId == coinId
    }

    /// Starts a Live Activity for the given crypto. Stops any existing activity first.
    func startTracking(crypto: any CryptoTrackable) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Stop any existing activity
        if currentActivity != nil {
            stopTracking()
        }

        let attributes = CryptoLiveActivityAttributes(
            coinId: crypto.trackingId,
            symbol: crypto.trackingSymbol,
            name: crypto.trackingName
        )

        cachedHigh24h = crypto.trackingHigh24h
        cachedLow24h = crypto.trackingLow24h

        let state = CryptoLiveActivityAttributes.ContentState(
            currentPrice: crypto.trackingPrice,
            priceChangePercentage24h: crypto.trackingChange24h,
            high24h: crypto.trackingHigh24h,
            low24h: crypto.trackingLow24h,
            lastUpdated: Date()
        )

        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(120))

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content
            )
            currentActivity = activity
            trackedCoinId = crypto.trackingId
        } catch {
            // Activity request failed — silently handle
        }
    }

    /// Updates the running Live Activity with fresh price data
    func updateTracking(
        price: Double,
        change24h: Double,
        high24h: Double,
        low24h: Double
    ) {
        guard let activity = currentActivity else { return }

        // Use new high/low if provided, otherwise keep cached
        let high = high24h > 0 ? high24h : cachedHigh24h
        let low = low24h > 0 ? low24h : cachedLow24h
        if high > 0 { cachedHigh24h = high }
        if low > 0 { cachedLow24h = low }

        let state = CryptoLiveActivityAttributes.ContentState(
            currentPrice: price,
            priceChangePercentage24h: change24h,
            high24h: high,
            low24h: low,
            lastUpdated: Date()
        )

        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(120))

        Task {
            await activity.update(content)
        }
    }

    /// Stops the current Live Activity and cleans up
    func stopTracking() {
        stopBackgroundPolling()

        if let activity = currentActivity {
            let state = activity.content.state
            let finalContent = ActivityContent(state: state, staleDate: nil)
            Task {
                await activity.end(finalContent, dismissalPolicy: .immediate)
            }
        }

        currentActivity = nil
        trackedCoinId = nil
        cachedHigh24h = 0
        cachedLow24h = 0
    }

    // MARK: - Background Polling

    /// Starts polling for price updates when the user leaves CryptoDetailView
    /// but the Live Activity is still active.
    func startBackgroundPolling() {
        guard let coinId = trackedCoinId, currentActivity != nil else { return }
        stopBackgroundPolling()

        backgroundPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pollingInterval ?? 30))
                guard !Task.isCancelled, let self else { break }

                do {
                    let result = try await self.service.fetchSingleCoinPrice(for: coinId)
                    await MainActor.run {
                        self.updateTracking(
                            price: result.price,
                            change24h: result.change24h,
                            high24h: result.high24h,
                            low24h: result.low24h
                        )
                    }
                } catch {
                    // Silently fail — next poll will retry
                }
            }
        }
    }

    /// Stops background polling (called when CryptoDetailView reappears)
    func stopBackgroundPolling() {
        backgroundPollingTask?.cancel()
        backgroundPollingTask = nil
    }

    // MARK: - Restore on Launch

    /// Checks for surviving Live Activities after app restart and resumes polling
    func restoreExistingActivity() {
        let activities = Activity<CryptoLiveActivityAttributes>.activities
        guard let existing = activities.first else { return }

        currentActivity = existing
        trackedCoinId = existing.attributes.coinId

        // Cache the last known high/low from the activity state
        cachedHigh24h = existing.content.state.high24h
        cachedLow24h = existing.content.state.low24h

        startBackgroundPolling()
    }

    // MARK: - Portfolio Dynamic Island

    /// Whether the portfolio balance is currently shown in the Dynamic Island
    var isShowingPortfolio: Bool { portfolioActivity != nil }

    /// Shows the portfolio balance in the Dynamic Island when the balance scrolls out of view
    func showPortfolioInDynamicIsland(balance: Double, changePercent: Double, changeAmount: Double) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Don't start if a crypto tracking activity is already running
        guard currentActivity == nil else { return }

        // Already showing — just update
        if portfolioActivity != nil {
            updatePortfolioDynamicIsland(balance: balance, changePercent: changePercent, changeAmount: changeAmount)
            return
        }

        let attributes = PortfolioLiveActivityAttributes()
        let state = PortfolioLiveActivityAttributes.ContentState(
            totalBalance: balance,
            changePercent: changePercent,
            changeAmount: changeAmount,
            lastUpdated: Date()
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(300))

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content
            )
            portfolioActivity = activity
        } catch {
            // Silently handle
        }
    }

    /// Updates the portfolio Dynamic Island with fresh values
    func updatePortfolioDynamicIsland(balance: Double, changePercent: Double, changeAmount: Double) {
        guard let activity = portfolioActivity else { return }

        let state = PortfolioLiveActivityAttributes.ContentState(
            totalBalance: balance,
            changePercent: changePercent,
            changeAmount: changeAmount,
            lastUpdated: Date()
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(300))

        Task {
            await activity.update(content)
        }
    }

    /// Hides the portfolio balance from the Dynamic Island when balance scrolls back into view
    func hidePortfolioDynamicIsland() {
        guard let activity = portfolioActivity else { return }

        let state = activity.content.state
        let finalContent = ActivityContent(state: state, staleDate: nil)
        Task {
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }
        portfolioActivity = nil
    }
}

// MARK: - Protocol for trackable crypto data

/// Allows both Cryptocurrency and other types to provide data for Live Activity
protocol CryptoTrackable {
    var trackingId: String { get }
    var trackingSymbol: String { get }
    var trackingName: String { get }
    var trackingPrice: Double { get }
    var trackingChange24h: Double { get }
    var trackingHigh24h: Double { get }
    var trackingLow24h: Double { get }
}
