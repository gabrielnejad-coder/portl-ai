import SwiftUI

/// Search tab — browse and search all cryptocurrencies
struct SearchView: View {

    @State private var viewModel = MarketViewModel()
    @State private var searchText = ""
    @State private var searchResults: [CoinSearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    /// Stores coin IDs for recent searches (resolved to full crypto objects via viewModel)
    @State private var recentCoinIds: [String] = []
    /// Cached search result data for coins not in market data, keyed by coin ID
    @State private var cachedSearchResults: [String: CoinSearchResult] = [:]
    @FocusState private var isSearchFocused: Bool

    private let recentSearchesKey = "recentCryptoSearches"
    private let cachedResultsKey = "cachedSearchResults"
    private let cryptoService = CryptoService()

    /// Local matches from already-loaded market data (instant)
    private var localMatches: [Cryptocurrency] {
        guard !searchText.isEmpty else { return [] }
        return viewModel.cryptocurrencies.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.symbol.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// API search results filtered to exclude coins already shown from local data
    private var apiOnlyResults: [CoinSearchResult] {
        let localIds = Set(localMatches.map(\.id))
        return searchResults.filter { !localIds.contains($0.id) }
    }

    /// Resolves stored coin IDs to full Cryptocurrency objects (or placeholders from cached results)
    private var recentCryptos: [Cryptocurrency] {
        recentCoinIds.compactMap { id in
            if let crypto = viewModel.cryptocurrencies.first(where: { $0.id == id }) {
                return crypto
            }
            // Fall back to cached search result data
            if let cached = cachedSearchResults[id] {
                return Cryptocurrency(
                    id: cached.id,
                    symbol: cached.symbol,
                    name: cached.name,
                    currentPrice: 0,
                    priceChangePercentage24h: 0,
                    marketCap: 0,
                    totalVolume: 0,
                    high24h: 0,
                    low24h: 0,
                    imageURL: cached.large ?? cached.thumb
                )
            }
            return nil
        }
    }

    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Content area
                if searchText.isEmpty && recentCryptos.isEmpty {
                    emptyState
                } else if searchText.isEmpty && !recentCryptos.isEmpty {
                    recentSearchesSection
                } else if !searchText.isEmpty && localMatches.isEmpty && apiOnlyResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    searchResultsList
                }

                // Search bar pinned at bottom, above tab bar
                searchBar
                    .padding(.horizontal, 40)
                    .padding(.bottom, 16)
                    .padding(.top, 8)
            }
            .onChange(of: searchText) { _, query in
                searchTask?.cancel()
                guard !query.isEmpty else {
                    searchResults = []
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    if let results = try? await cryptoService.searchCoins(query: query) {
                        searchResults = results
                    }
                }
            }
            .scrollEdgeEffectHidden(true, for: .all)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: Cryptocurrency.self) { crypto in
                CryptoDetailView(crypto: crypto)
            }
            .task {
                loadRecentSearches()
                await viewModel.loadMarketData()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("Search for a cryptocurrency")
                .font(.publicaPlay(size: 17))
                .foregroundStyle(.secondary)

            Text("Find prices, charts, and market data")
                .font(.publicaPlay(size: 14))
                .foregroundStyle(.secondary.opacity(0.7))

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search", text: $searchText)
                    .font(.publicaPlay(size: 16))
                    .focused($isSearchFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.haptic)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .glassEffect(in: .capsule)

            if isSearchFocused {
                Button("Cancel") {
                    searchText = ""
                    isSearchFocused = false
                }
                .font(.publicaPlay(size: 14))
                .buttonStyle(.haptic)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: isSearchFocused)
    }

    // MARK: - Recent Searches

    private var recentSearchesSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recent")
                        .font(.publicaPlay(size: 16))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            recentCoinIds.removeAll()
                            UserDefaults.standard.removeObject(forKey: recentSearchesKey)
                        }
                    } label: {
                        Text("Clear All")
                            .font(.publicaPlay(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.haptic)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                ForEach(recentCryptos) { crypto in
                    NavigationLink(value: crypto) {
                        MarketRowView(crypto: crypto, showFavorite: true, showVerified: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.haptic)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Local matches (full Cryptocurrency objects — have price data)
                ForEach(localMatches) { crypto in
                    Button {
                        saveRecent(crypto.id)
                        navigationPath.append(crypto)
                    } label: {
                        MarketRowView(crypto: crypto, showFavorite: false, showVerified: true)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.haptic)
                    .padding(.horizontal, 16)
                }

                // API-only results (coins not in local market data)
                ForEach(apiOnlyResults) { result in
                    SearchResultRow(result: result) {
                        saveRecent(result.id)
                        cacheSearchResult(result)
                        resolveAndNavigate(result)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func resolveAndNavigate(_ result: CoinSearchResult) {
        // Use existing full data if available, otherwise create a lightweight
        // placeholder so navigation is instant. The detail view's live updates
        // will fetch real price/market data within seconds.
        if let existing = viewModel.cryptocurrencies.first(where: { $0.id == result.id }) {
            navigationPath.append(existing)
        } else {
            let placeholder = Cryptocurrency(
                id: result.id,
                symbol: result.symbol,
                name: result.name,
                currentPrice: 0,
                priceChangePercentage24h: 0,
                marketCap: 0,
                totalVolume: 0,
                high24h: 0,
                low24h: 0,
                imageURL: result.large ?? result.thumb
            )
            navigationPath.append(placeholder)
        }
    }

    // MARK: - Recent Searches Persistence

    private func loadRecentSearches() {
        recentCoinIds = UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []
        // Load cached search result data
        if let data = UserDefaults.standard.data(forKey: cachedResultsKey),
           let decoded = try? JSONDecoder().decode([String: CoinSearchResult].self, from: data) {
            cachedSearchResults = decoded
        }
    }

    private func saveRecent(_ coinId: String) {
        recentCoinIds.removeAll { $0 == coinId }
        recentCoinIds.insert(coinId, at: 0)
        if recentCoinIds.count > 10 {
            recentCoinIds = Array(recentCoinIds.prefix(10))
        }
        UserDefaults.standard.set(recentCoinIds, forKey: recentSearchesKey)
        saveCachedResults()
    }

    private func cacheSearchResult(_ result: CoinSearchResult) {
        cachedSearchResults[result.id] = result
        saveCachedResults()
    }

    private func saveCachedResults() {
        // Only keep cached results for IDs in recentCoinIds
        let relevantIds = Set(recentCoinIds)
        let filtered = cachedSearchResults.filter { relevantIds.contains($0.key) }
        if let data = try? JSONEncoder().encode(filtered) {
            UserDefaults.standard.set(data, forKey: cachedResultsKey)
        }
    }


}

// MARK: - Search Result Row (API results without full market data)

private struct SearchResultRow: View {

    let result: CoinSearchResult
    let onTap: () -> Void
    private var favorites: FavoritesManager { FavoritesManager.shared }

    var body: some View {
        HStack(spacing: 14) {
            // Tappable row content
            Button {
                onTap()
            } label: {
                HStack(spacing: 14) {
                    // Coin icon
                    ZStack {
                        Circle()
                            .fill(Color.brandNavy.opacity(0.06))
                            .frame(width: 52, height: 52)

                        if let thumb = result.large ?? result.thumb,
                           let url = URL(string: thumb) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 52, height: 52)
                                    .clipShape(Circle())
                            } placeholder: {
                                Text(String(result.symbol.prefix(1)).uppercased())
                                    .font(.publicaPlay(size: 18))
                                    .foregroundStyle(.primary.opacity(0.6))
                            }
                        } else {
                            Text(String(result.symbol.prefix(1)).uppercased())
                                .font(.publicaPlay(size: 18))
                                .foregroundStyle(.primary.opacity(0.6))
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 4) {
                            Text(result.symbol.uppercased())
                                .font(.publicaPlay(size: 20))
                            if result.marketCapRank != nil {
                                Image("WavyCheck")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                            }
                        }
                        Text(result.name)
                            .font(.publicaPlay(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if let rank = result.marketCapRank {
                        Text("#\(rank)")
                            .font(.publicaPlay(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.haptic)

            // Favorite button — separate from the row tap
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    favorites.toggle(result.id)
                }
            } label: {
                Image(systemName: favorites.isFavorited(result.id) ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(favorites.isFavorited(result.id) ? .yellow : .primary.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.haptic)
        }
    }
}

#Preview {
    SearchView()
}
