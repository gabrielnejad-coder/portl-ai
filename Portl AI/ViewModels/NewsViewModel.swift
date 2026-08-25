import Foundation
import SwiftUI

/// Manages news feed state and data fetching via Google News RSS
@MainActor
@Observable
final class NewsViewModel {

    var articles: [NewsArticle] = []
    var isLoading = false
    var errorMessage: String?
    var selectedFilter: NewsFilter = .all
    var selectedImpact: ImpactLevel? = nil  // nil = show all

    /// Market data used to resolve coin icon URLs for articles
    var cryptocurrencies: [Cryptocurrency] = []

    /// Articles filtered by impact level
    var filteredArticles: [NewsArticle] {
        guard let impact = selectedImpact else { return articles }
        return articles.filter { $0.impact >= impact }
    }

    /// Curated X (Twitter) accounts for crypto news
    static let xAccounts: [XFeedAccount] = [
        XFeedAccount(handle: "CoinDesk", displayName: "CoinDesk", category: "News"),
        XFeedAccount(handle: "Cointelegraph", displayName: "Cointelegraph", category: "News"),
        XFeedAccount(handle: "whale_alert", displayName: "Whale Alert", category: "Alerts"),
        XFeedAccount(handle: "WatcherGuru", displayName: "Watcher.Guru", category: "News"),
        XFeedAccount(handle: "lookonchain", displayName: "Lookonchain", category: "On-chain"),
        XFeedAccount(handle: "DefiLlama", displayName: "DeFi Llama", category: "DeFi"),
    ]

    var filteredXAccounts: [XFeedAccount] {
        Self.xAccounts
    }

    /// Load news articles from Google News RSS
    func loadNews() async {
        isLoading = true
        errorMessage = nil
        do {
            let filter = selectedFilter

            // Fetch news — pass any loaded cryptos for icon enrichment
            let rawArticles = try await NewsService.shared.fetchNews(filter: filter, cryptocurrencies: cryptocurrencies)
            articles = rawArticles
            isLoading = false

            // For crypto filters, enrich with coin icons in the background (non-blocking)
            if filter.isCryptoFilter && cryptocurrencies.isEmpty {
                let cryptos = (try? await CryptoService.shared.fetchTopCryptos(limit: 50)) ?? []
                if !cryptos.isEmpty {
                    cryptocurrencies = cryptos
                    articles = rawArticles.map { enrichWithCoinIcon($0, cryptos: cryptos) }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// Attach a coin icon URL to articles that mention a known crypto symbol
    private func enrichWithCoinIcon(_ article: NewsArticle, cryptos: [Cryptocurrency]) -> NewsArticle {
        guard !article.mentionedSymbols.isEmpty, article.imageURL == nil,
              let symbol = article.mentionedSymbols.first,
              let crypto = cryptos.first(where: { $0.symbol.uppercased() == symbol }),
              let imgURL = crypto.imageURL, !imgURL.isEmpty else {
            return article
        }
        return NewsArticle(
            id: article.id, title: article.title,
            description: article.description, publishedDate: article.publishedDate,
            kind: article.kind, impact: article.impact,
            imageURL: imgURL, articleURL: article.articleURL,
            sourceName: article.sourceName, mentionedSymbols: article.mentionedSymbols
        )
    }

    /// Relative time string like "2h ago", "5m ago"
    static func relativeTime(for date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if hours < 24 { return "\(hours)h ago" }
        if days == 1 { return "Yesterday" }
        return "\(days)d ago"
    }
}
