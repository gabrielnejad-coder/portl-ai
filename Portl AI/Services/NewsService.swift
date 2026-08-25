import Foundation

/// Fetches news from Google News RSS feeds
final class NewsService {

    static let shared = NewsService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    // MARK: - In-memory cache (2-minute TTL)

    private var cache: [String: (articles: [NewsArticle], timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 120

    // MARK: - Top-level coin lookup table

    /// Common crypto symbols → CoinGecko IDs for matching headlines to coin images
    private static let symbolToID: [String: String] = [
        "BTC": "bitcoin", "ETH": "ethereum", "BNB": "binancecoin",
        "SOL": "solana", "XRP": "ripple", "ADA": "cardano",
        "DOGE": "dogecoin", "AVAX": "avalanche-2", "DOT": "polkadot",
        "LINK": "chainlink", "MATIC": "matic-network", "SHIB": "shiba-inu",
        "LTC": "litecoin", "UNI": "uniswap", "ATOM": "cosmos",
        "XLM": "stellar", "NEAR": "near", "APT": "aptos",
        "ARB": "arbitrum", "OP": "optimism", "FIL": "filecoin",
        "AAVE": "aave", "SUI": "sui", "SEI": "sei-network",
        "INJ": "injective-protocol", "TIA": "celestia",
        "PEPE": "pepe", "WIF": "dogwifcoin", "BONK": "bonk",
        "TON": "the-open-network", "TRX": "tron",
    ]

    /// Common full names (case-insensitive matching)
    private static let nameToSymbol: [String: String] = [
        "bitcoin": "BTC", "ethereum": "ETH", "solana": "SOL",
        "ripple": "XRP", "cardano": "ADA", "dogecoin": "DOGE",
        "polkadot": "DOT", "chainlink": "LINK", "litecoin": "LTC",
        "uniswap": "UNI", "avalanche": "AVAX", "cosmos": "ATOM",
    ]

    // MARK: - Public API

    /// Fetch news articles for a given filter via Google News RSS
    func fetchNews(filter: NewsFilter = .all, cryptocurrencies: [Cryptocurrency] = []) async throws -> [NewsArticle] {
        let cacheKey = filter.rawValue

        // Return cached articles if still fresh
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.articles
        }

        let articles = try await fetchGoogleNews(query: filter.googleNewsQuery)

        // Enrich crypto articles with coin image URLs
        let enriched = articles.map { article in
            enrichWithCoinImages(article, cryptos: cryptocurrencies)
        }

        cache[cacheKey] = (enriched, Date())
        return enriched
    }

    /// Fetch crypto news for a specific coin via Google News RSS
    func fetchCryptoNews(symbol: String, limit: Int = 3) async throws -> [NewsArticle] {
        let coinName = Self.nameToSymbol.first(where: { $0.value == symbol.uppercased() })?.key ?? symbol
        let query = "\(coinName) OR \(symbol) crypto"
        let articles = try await fetchGoogleNews(query: query)
        let sorted = articles.sorted { a, b in
            if a.impact != b.impact { return a.impact > b.impact }
            return a.publishedDate > b.publishedDate
        }
        return Array(sorted.prefix(limit))
    }

    // MARK: - Google News RSS

    private func fetchGoogleNews(query: String) async throws -> [NewsArticle] {
        var components = URLComponents(string: "https://news.google.com/rss/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "hl", value: "en-US"),
            URLQueryItem(name: "gl", value: "US"),
            URLQueryItem(name: "ceid", value: "US:en"),
        ]

        guard let url = components.url else { throw URLError(.badURL) }

        let (data, _) = try await session.data(from: url)
        let parser = GoogleNewsRSSParser(data: data)
        return parser.parse()
    }

    // MARK: - Coin Symbol Matching

    /// Extract crypto symbols mentioned in a headline (e.g. "BTC surges" → ["BTC"])
    static func extractSymbols(from title: String) -> [String] {
        var found: [String] = []

        // Check for explicit ticker symbols (uppercase 2-5 letter words)
        let words = title.components(separatedBy: CharacterSet.alphanumerics.inverted)
        for word in words {
            let upper = word.uppercased()
            if word == upper, upper.count >= 2, upper.count <= 5, symbolToID[upper] != nil {
                if !found.contains(upper) { found.append(upper) }
            }
        }

        // Check for full names
        let lower = title.lowercased()
        for (name, symbol) in nameToSymbol {
            if lower.contains(name), !found.contains(symbol) {
                found.append(symbol)
            }
        }

        return found
    }

    /// Enrich an article with coin image URLs from loaded market data
    private func enrichWithCoinImages(_ article: NewsArticle, cryptos: [Cryptocurrency]) -> NewsArticle {
        guard !article.mentionedSymbols.isEmpty, !cryptos.isEmpty else { return article }

        for symbol in article.mentionedSymbols {
            if let coinID = Self.symbolToID[symbol],
               let crypto = cryptos.first(where: { $0.id == coinID }),
               let imgURL = crypto.imageURL, !imgURL.isEmpty {
                return NewsArticle(
                    id: article.id,
                    title: article.title,
                    description: article.description,
                    publishedDate: article.publishedDate,
                    kind: article.kind,
                    impact: article.impact,
                    imageURL: imgURL,
                    articleURL: article.articleURL,
                    sourceName: article.sourceName,
                    mentionedSymbols: article.mentionedSymbols
                )
            }
        }
        return article
    }
}

// extenMARK: - Google News RSS Parser

/// Parses Google News RSS XML into NewsArticle objects
private final class GoogleNewsRSSParser: NSObject, XMLParserDelegate {

    private let data: Data
    private var articles: [NewsArticle] = []

    // Parsing state
    private var inItem = false
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentPubDate = ""
    private var currentSource = ""

    /// RFC 2822 date formatter for RSS pubDate
    private static let rssDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    init(data: Data) {
        self.data = data
    }

    func parse() -> [NewsArticle] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return articles
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if elementName == "item" {
            inItem = true
            currentTitle = ""
            currentLink = ""
            currentPubDate = ""
            currentSource = ""
        }
        currentElement = elementName
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "link": currentLink += string
        case "pubDate": currentPubDate += string
        case "source": currentSource += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard elementName == "item", inItem else { return }
        inItem = false

        let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = currentSource.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty, !link.isEmpty else { return }

        let date = Self.rssDateFormatter.date(from: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)) ?? Date()
        let symbols = NewsService.extractSymbols(from: title)
        let stableID = "gn-\(title.hashValue)-\(link.hashValue)"

        let article = NewsArticle(
            id: stableID,
            title: title,
            description: "",
            publishedDate: date,
            kind: "news",
            impact: ImpactLevel.estimate(from: title),
            imageURL: nil,
            articleURL: link,
            sourceName: source.isEmpty ? nil : source,
            mentionedSymbols: symbols
        )
        articles.append(article)
    }
}
