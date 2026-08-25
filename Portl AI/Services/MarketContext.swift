import Foundation

/// Gathers live market data and recent news into a formatted context string
/// that gets injected into the AI system prompt so GPT-4o can give informed answers.
@MainActor
struct MarketContext {

    /// Builds a concise market snapshot from current data
    static func buildContextString(
        cryptos: [Cryptocurrency],
        news: [NewsArticle],
        favoritedIds: Set<String>
    ) -> String {
        var lines: [String] = []

        lines.append("=== LIVE MARKET SNAPSHOT (as of \(formattedNow())) ===")
        lines.append("")

        // Top coins by market cap
        let top = Array(cryptos.prefix(15))
        if !top.isEmpty {
            lines.append("TOP COINS:")
            for coin in top {
                let dir = coin.priceChangePercentage24h >= 0 ? "▲" : "▼"
                let pct = String(format: "%.2f", abs(coin.priceChangePercentage24h))
                lines.append("  \(coin.symbol.uppercased()): \(coin.currentPrice.asDollars) \(dir)\(pct)% 24h | MCap: \(coin.marketCap.asCompactMC) | Vol: \(coin.totalVolume.asCompactMC)")
            }
            lines.append("")
        }

        // User's favorited/watched coins (if any differ from top)
        let topIds = Set(top.map(\.id))
        let watchedCoins = cryptos.filter { favoritedIds.contains($0.id) && !topIds.contains($0.id) }
        if !watchedCoins.isEmpty {
            lines.append("USER'S WATCHLIST (additional):")
            for coin in watchedCoins {
                let dir = coin.priceChangePercentage24h >= 0 ? "▲" : "▼"
                let pct = String(format: "%.2f", abs(coin.priceChangePercentage24h))
                lines.append("  \(coin.symbol.uppercased()): \(coin.currentPrice.asDollars) \(dir)\(pct)% 24h")
            }
            lines.append("")
        }

        // Market overview stats
        if !cryptos.isEmpty {
            let totalMC = cryptos.reduce(0.0) { $0 + $1.marketCap }
            let avgChange = cryptos.reduce(0.0) { $0 + $1.priceChangePercentage24h } / Double(cryptos.count)
            let gainers = cryptos.filter { $0.priceChangePercentage24h > 0 }.count
            let losers = cryptos.count - gainers

            lines.append("MARKET OVERVIEW:")
            lines.append("  Total market cap (top \(cryptos.count)): \(totalMC.asCompactMC)")
            lines.append("  Avg 24h change: \(String(format: "%.2f", avgChange))%")
            lines.append("  Gainers/Losers: \(gainers)/\(losers)")

            // Top gainer and loser
            if let topGainer = cryptos.max(by: { $0.priceChangePercentage24h < $1.priceChangePercentage24h }) {
                lines.append("  Top gainer: \(topGainer.symbol.uppercased()) +\(String(format: "%.2f", topGainer.priceChangePercentage24h))%")
            }
            if let topLoser = cryptos.min(by: { $0.priceChangePercentage24h < $1.priceChangePercentage24h }) {
                lines.append("  Top loser: \(topLoser.symbol.uppercased()) \(String(format: "%.2f", topLoser.priceChangePercentage24h))%")
            }
            lines.append("")
        }

        // Recent news headlines
        let recentNews = Array(news.sorted { $0.publishedDate > $1.publishedDate }.prefix(10))
        if !recentNews.isEmpty {
            lines.append("RECENT NEWS HEADLINES:")
            for article in recentNews {
                let age = NewsViewModel.relativeTime(for: article.publishedDate)
                let impact = article.impact == .high ? " [HIGH IMPACT]" : (article.impact == .medium ? " [MEDIUM]" : "")
                let source = article.sourceName.map { " — \($0)" } ?? ""
                lines.append("  • \(article.title)\(source) (\(age))\(impact)")
            }
            lines.append("")
        }

        lines.append("=== END MARKET SNAPSHOT ===")

        return lines.joined(separator: "\n")
    }

    private static func formattedNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy h:mm a z"
        f.timeZone = .current
        return f.string(from: Date())
    }
}
