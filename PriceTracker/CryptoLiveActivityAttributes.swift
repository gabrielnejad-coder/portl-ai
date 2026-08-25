import ActivityKit
import Foundation

/// Defines the data model for the crypto price tracking Live Activity.
/// This file must be compiled in both the main app and PriceTracker widget extension targets.
struct CryptoLiveActivityAttributes: ActivityAttributes {

    // MARK: - Static Data (set when activity starts, never changes)

    let coinId: String
    let symbol: String
    let name: String

    // MARK: - Dynamic Data (updated via Activity.update every 30s)

    struct ContentState: Codable, Hashable {
        let currentPrice: Double
        let priceChangePercentage24h: Double
        let high24h: Double
        let low24h: Double
        let lastUpdated: Date

        var isPositive: Bool { priceChangePercentage24h >= 0 }

        var formattedPrice: String {
            let decimals: Int
            let abs = Swift.abs(currentPrice)
            switch abs {
            case 1...:          decimals = 2
            case 0.01..<1:      decimals = 4
            case 0.0001..<0.01: decimals = 6
            default:            decimals = 8
            }
            return String(format: "$%.\(decimals)f", currentPrice)
        }

        var formattedChange: String {
            let sign = priceChangePercentage24h >= 0 ? "+" : ""
            return String(format: "%@%.2f%%", sign, priceChangePercentage24h)
        }
    }
}
