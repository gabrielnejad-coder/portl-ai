import ActivityKit
import Foundation

/// Defines the data model for the portfolio balance Dynamic Island display.
/// Shown when the user scrolls past the balance on the dashboard.
struct PortfolioLiveActivityAttributes: ActivityAttributes {

    // MARK: - Static Data (no static fields needed)

    // MARK: - Dynamic Data

    struct ContentState: Codable, Hashable {
        let totalBalance: Double
        let changePercent: Double
        let changeAmount: Double
        let lastUpdated: Date

        var isPositive: Bool { changePercent >= 0 }

        var formattedBalance: String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencySymbol = "$"
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
            return formatter.string(from: NSNumber(value: totalBalance)) ?? "$0.00"
        }

        var formattedChange: String {
            let sign = changePercent >= 0 ? "+" : ""
            return String(format: "%@%.2f%%", sign, changePercent)
        }

        var formattedChangeAmount: String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencySymbol = "$"
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
            let formatted = formatter.string(from: NSNumber(value: abs(changeAmount))) ?? "$0.00"
            let sign = changeAmount >= 0 ? "+" : "-"
            return "\(sign)\(formatted)"
        }
    }
}
