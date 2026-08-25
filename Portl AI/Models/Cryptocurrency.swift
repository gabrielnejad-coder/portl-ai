import Foundation

/// Represents a cryptocurrency with its market data
struct Cryptocurrency: Identifiable, Codable, Hashable {
    let id: String
    let symbol: String
    let name: String
    var currentPrice: Double
    var priceChangePercentage24h: Double
    var marketCap: Double
    var totalVolume: Double
    var high24h: Double
    var low24h: Double
    var imageURL: String?
    var sparklineIn7d: SparklineData?

    enum CodingKeys: String, CodingKey {
        case id, symbol, name
        case currentPrice = "current_price"
        case priceChangePercentage24h = "price_change_percentage_24h"
        case marketCap = "market_cap"
        case totalVolume = "total_volume"
        case high24h = "high_24h"
        case low24h = "low_24h"
        case imageURL = "image"
        case sparklineIn7d = "sparkline_in_7d"
    }
}

/// 7-day sparkline price data from CoinGecko
struct SparklineData: Codable, Hashable {
    let price: [Double]
}

/// Formats a Double as a dollar string
extension Double {
    /// Dynamic precision for coin prices — shows more decimals for tiny values.
    var asDollars: String {
        let decimals = PriceText.decimalPlaces(for: self)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.internationalCurrencySymbol = "$"
        formatter.maximumFractionDigits = decimals
        formatter.minimumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }

    /// Fixed 2-decimal format for portfolio values, holdings, and other USD amounts.
    var asCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.internationalCurrencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }

    /// Compact format like "$1.3T", "$245.6B", "$12.4M"
    var asCompactMC: String {
        switch abs(self) {
        case 1_000_000_000_000...:
            return String(format: "$%.1fT", self / 1_000_000_000_000)
        case 1_000_000_000...:
            return String(format: "$%.1fB", self / 1_000_000_000)
        case 1_000_000...:
            return String(format: "$%.1fM", self / 1_000_000)
        default:
            return asDollars
        }
    }
}

/// A simplified price data point for charting
struct PriceDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let price: Double
}

// MARK: - Live Activity Tracking

extension Cryptocurrency: CryptoTrackable {
    var trackingId: String { id }
    var trackingSymbol: String { symbol }
    var trackingName: String { name }
    var trackingPrice: Double { currentPrice }
    var trackingChange24h: Double { priceChangePercentage24h }
    var trackingHigh24h: Double { high24h }
    var trackingLow24h: Double { low24h }
}
