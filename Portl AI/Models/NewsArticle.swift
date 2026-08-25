import Foundation

/// Impact level estimated from headline keywords
enum ImpactLevel: Int, CaseIterable, Comparable, Identifiable {
    case low = 1
    case medium = 2
    case high = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var icon: String {
        switch self {
        case .low: return "gauge.with.dots.needle.0percent"
        case .medium: return "gauge.with.dots.needle.50percent"
        case .high: return "gauge.with.dots.needle.100percent"
        }
    }

    var color: String {
        switch self {
        case .low: return "gray"
        case .medium: return "yellow"
        case .high: return "red"
        }
    }

    static func < (lhs: ImpactLevel, rhs: ImpactLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Estimate impact from a headline string
    static func estimate(from title: String) -> ImpactLevel {
        let t = title.lowercased()

        let highKeywords = [
            "crash", "crashes", "plunge", "plunges", "plummets", "collapse",
            "surge", "surges", "soar", "soars", "skyrocket", "spike",
            "breaking", "urgent", "emergency", "war", "invasion", "attack",
            "sanctions", "ban", "default", "recession", "shutdown",
            "rate hike", "rate cut", "fed raises", "fed cuts",
            "impeach", "indictment", "arrest", "assassination",
            "all-time high", "all-time low", "record high", "record low",
            "hack", "exploit", "billion", "trillion",
        ]

        let mediumKeywords = [
            "rise", "rises", "fall", "falls", "drop", "drops", "gain", "gains",
            "rally", "dip", "volatil", "inflation", "gdp", "employment",
            "report", "announce", "launch", "approval", "ruling",
            "opec", "federal reserve", "sec", "regulation",
            "election", "vote", "poll", "debate",
            "partnership", "acquisition", "merger", "ipo",
            "million", "upgrade", "downgrade",
        ]

        if highKeywords.contains(where: { t.contains($0) }) { return .high }
        if mediumKeywords.contains(where: { t.contains($0) }) { return .medium }
        return .low
    }
}

/// Represents a news article fetched from Google News RSS
struct NewsArticle: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let publishedDate: Date
    let kind: String
    let impact: ImpactLevel
    let imageURL: String?       // Coin icon URL (enriched from market data)
    let articleURL: String?     // Full article URL from Google News
    let sourceName: String?     // Source name from RSS <source> element
    /// Coin symbol(s) detected in the headline (e.g. "BTC", "ETH")
    let mentionedSymbols: [String]

    /// Source label — uses explicit sourceName if available
    var source: String {
        if let name = sourceName, !name.isEmpty { return name }
        return "Google News"
    }

    /// Whether this article has a real thumbnail image
    var hasImage: Bool { imageURL != nil && !imageURL!.isEmpty }

    /// Whether this article has a tappable URL
    var hasURL: Bool { articleURL != nil && !articleURL!.isEmpty }
}

/// Filter / category for news feed
enum NewsFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case bitcoin = "Bitcoin"
    case ethereum = "Ethereum"
    case altcoins = "Altcoins"
    case defi = "DeFi"
    case nft = "NFT"
    case economics = "Economics"
    case politics = "Politics"
    case oilEnergy = "Oil & Energy"

    var id: String { rawValue }

    /// SF Symbol icon for each filter
    var icon: String {
        switch self {
        case .all: return "globe"
        case .bitcoin: return "bitcoinsign.circle"
        case .ethereum: return "diamond"
        case .altcoins: return "chart.line.uptrend.xyaxis"
        case .defi: return "link"
        case .nft: return "square.stack.3d.up"
        case .economics: return "chart.bar"
        case .politics: return "building.columns"
        case .oilEnergy: return "bolt.fill"
        }
    }

    /// Whether this filter is a crypto-related category
    var isCryptoFilter: Bool {
        switch self {
        case .economics, .politics, .oilEnergy: return false
        default: return true
        }
    }

    /// Google News RSS search query for each filter
    var googleNewsQuery: String {
        switch self {
        case .all: return "cryptocurrency OR crypto OR bitcoin OR blockchain"
        case .bitcoin: return "bitcoin OR BTC"
        case .ethereum: return "ethereum OR ETH"
        case .altcoins: return "altcoin OR solana OR XRP OR cardano OR dogecoin OR avalanche"
        case .defi: return "DeFi OR \"decentralized finance\" OR DEX OR yield farming"
        case .nft: return "NFT OR \"non-fungible token\" OR digital art crypto"
        case .economics: return "economy OR economics OR GDP OR inflation OR \"interest rate\" OR recession"
        case .politics: return "politics OR election OR congress OR senate OR government OR policy"
        case .oilEnergy: return "oil OR \"crude oil\" OR energy OR OPEC OR \"natural gas\" OR petroleum"
        }
    }
}

/// Represents a curated X (Twitter) account for crypto news
struct XFeedAccount: Identifiable {
    let id = UUID()
    let handle: String
    let displayName: String
    let category: String
}
