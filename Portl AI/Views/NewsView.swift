import SwiftUI
import SafariServices

/// News tab — aggregated crypto news from Google News RSS and curated X feeds
struct NewsView: View {

    @State private var viewModel = NewsViewModel()
    @State private var showImpactFilter = false
    @State private var visibleCount = 10
    @State private var safariURL: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    categoryPicker
                        .scrollTransition(topLeading: .interactive,
                                          bottomTrailing: .identity) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0)
                                .blur(radius: phase.isIdentity ? 0 : 6)
                        }

                    // Only show X feeds for crypto filters
                    if viewModel.selectedFilter.isCryptoFilter {
                        xFeedsSection
                            .scrollTransition(topLeading: .interactive,
                                              bottomTrailing: .identity) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0)
                                    .blur(radius: phase.isIdentity ? 0 : 6)
                            }
                    }

                    newsSection
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 20)
            }
            .scrollEdgeEffectHidden(true, for: .all)
            
            .navigationTitle("News")
            .navigationBarTitleDisplayMode(.inline)
            
            .task { await viewModel.loadNews() }
            .refreshable { await viewModel.loadNews() }
            .onChange(of: viewModel.selectedFilter) {
                visibleCount = 10
                Task { await viewModel.loadNews() }
            }
            .onChange(of: viewModel.selectedImpact) {
                visibleCount = 10
            }
            .fullScreenCover(item: $safariURL) { url in
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NewsFilter.allCases) { filter in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            viewModel.selectedFilter = filter
                        }
                    } label: {
                        let isSelected = viewModel.selectedFilter == filter
                        HStack(spacing: 6) {
                            Image(systemName: filter.icon)
                                .font(.system(size: 12, weight: .medium))
                            Text(filter.rawValue)
                                .font(.publicaPlay(size: 13))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .foregroundStyle(isSelected ? .white : .secondary)
                    }
                    .buttonStyle(.haptic)
                    .glassEffect(in: .capsule)
                    .opacity(viewModel.selectedFilter == filter ? 1.0 : 0.5)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Trending on X

    private var xFeedsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trending on X")
                .font(.publicaPlay(size: 24))
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.filteredXAccounts) { account in
                        xPostCard(account)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    /// Simple X account card — display name, handle, category badge, tap to open
    private func xPostCard(_ account: XFeedAccount) -> some View {
        Button {
            openXProfile(handle: account.handle)
        } label: {
            HStack(spacing: 10) {
                // Letter avatar
                Circle()
                    .fill(Color.brandNavy.opacity(0.06))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(String(account.displayName.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.7))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(account.displayName)
                            .font(.publicaPlay(size: 13))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                    }
                    Text("@\(account.handle)")
                        .font(.publicaPlay(size: 11))
                        .foregroundStyle(.primary.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(account.category)
                    .font(.publicaPlay(size: 10))
                    .foregroundStyle(.primary.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5), in: Capsule())
            }
            .padding(12)
            .frame(width: 220)
            .glassEffect(in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.haptic)
    }

    /// Opens X profile — tries X app first, then in-app Safari
    private func openXProfile(handle: String) {
        let xAppURL = URL(string: "twitter://user?screen_name=\(handle)")!
        let webURL = URL(string: "https://x.com/\(handle)")!

        if UIApplication.shared.canOpenURL(xAppURL) {
            openURL(xAppURL)
        } else {
            safariURL = webURL
        }
    }

    // MARK: - News Articles

    private var newsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with filter button — no globe icon
            HStack(spacing: 8) {
                Text("Latest Headlines")
                    .font(.publicaPlay(size: 24))

                Spacer()

                // Impact filter button
                Menu {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { viewModel.selectedImpact = nil }
                    } label: {
                        HStack {
                            Text("All Impact")
                            if viewModel.selectedImpact == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(ImpactLevel.allCases) { level in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                viewModel.selectedImpact = level
                            }
                        } label: {
                            HStack {
                                Label(level.label, systemImage: level.icon)
                                if viewModel.selectedImpact == level {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: viewModel.selectedImpact?.icon ?? "line.3.horizontal.decrease")
                            .font(.system(size: 12, weight: .medium))
                        if let impact = viewModel.selectedImpact {
                            Text(impact.label)
                                .font(.publicaPlay(size: 12))
                        }
                    }
                    .foregroundStyle(viewModel.selectedImpact != nil ? impactColor(viewModel.selectedImpact!) : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(in: .capsule)
                }
            }

            if viewModel.isLoading && viewModel.articles.isEmpty {
                loadingState
            } else if let error = viewModel.errorMessage, viewModel.articles.isEmpty {
                errorState(error)
            } else if viewModel.filteredArticles.isEmpty {
                if viewModel.selectedImpact != nil {
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("No \(viewModel.selectedImpact!.label.lowercased()) impact articles")
                            .font(.publicaPlay(size: 14))
                            .foregroundStyle(.secondary)
                        Button("Clear filter") {
                            withAnimation { viewModel.selectedImpact = nil }
                        }
                        .font(.publicaPlay(size: 13))
                        .buttonStyle(.glass)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    emptyState
                }
            } else {
                let allArticles = viewModel.filteredArticles
                let remaining = Array(allArticles.dropFirst())
                let visible = Array(remaining.prefix(visibleCount))
                let hasMore = remaining.count > visibleCount

                LazyVStack(spacing: 10) {
                    // Featured top article — Aurora card, title only
                    if let featured = allArticles.first {
                        featuredArticleCard(featured)
                            .padding(.bottom, 8)
                    }

                    // Remaining articles
                    ForEach(visible, id: \.id) { article in
                        articleRow(article)
                    }

                    // View more button
                    if hasMore {
                        Button {
                            withAnimation(.snappy(duration: 0.3)) {
                                visibleCount += 10
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text("View More")
                                    .font(.publicaPlay(size: 14))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.haptic)
                        .glassEffect(in: .rect(cornerRadius: 12))
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    // MARK: - Featured Article Card (Aurora — title only, no badge, no image)

    private func featuredArticleCard(_ article: NewsArticle) -> some View {
        Button {
            if let urlStr = article.articleURL, let url = URL(string: urlStr) {
                safariURL = url
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Source + time
                HStack(spacing: 8) {
                    articleSourceIcon(article, size: 22)

                    Text(article.source)
                        .font(.publicaPlay(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(NewsViewModel.relativeTime(for: article.publishedDate))
                        .font(.publicaPlay(size: 12))
                        .foregroundStyle(.primary.opacity(0.4))
                }

                // Headline only
                Text(article.title)
                    .font(.publicaPlay(size: 20))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            .padding(18)
            .background {
                AuroraGradientBorder(cornerRadius: 18)
            }
        }
        .buttonStyle(.elevating)
    }

    // MARK: - Standard Article Row (title + source icon, badge only for high impact)

    private func articleRow(_ article: NewsArticle) -> some View {
        Button {
            if let urlStr = article.articleURL, let url = URL(string: urlStr) {
                safariURL = url
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    // Source row
                    HStack(spacing: 6) {
                        articleSourceIcon(article, size: 20)

                        Text(article.source)
                            .font(.publicaPlay(size: 11))
                            .foregroundStyle(.secondary)

                        Spacer()

                        // Aurora impact badge — only for high impact
                        if article.impact == .high {
                            ImpactBadge(impact: article.impact, impactColor: .red)
                        }

                        Text(NewsViewModel.relativeTime(for: article.publishedDate))
                            .font(.publicaPlay(size: 11))
                            .foregroundStyle(.primary.opacity(0.35))
                    }

                    // Headline only — no description
                    Text(article.title)
                        .font(.publicaPlay(size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .glassEffect(in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.elevating)
    }

    // MARK: - Source Icons

    /// Source icon — coin icon for crypto articles, letter circle for others
    private func articleSourceIcon(_ article: NewsArticle, size: CGFloat) -> some View {
        Group {
            if let firstSymbol = article.mentionedSymbols.first,
               let imgURL = article.imageURL {
                CryptoIconView(imageURL: imgURL, symbol: firstSymbol, size: size)
            } else {
                Circle()
                    .fill(Color.brandNavy.opacity(size > 20 ? 0.08 : 0.06))
                    .frame(width: size, height: size)
                    .overlay {
                        Text(String(article.source.prefix(1)).uppercased())
                            .font(.system(size: size * 0.4, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.8))
                    }
            }
        }
    }

    // MARK: - Impact Indicators
    // Uses the shared ImpactBadge from ArticleDetailView (aurora gradient for high impact)

    private func impactColor(_ impact: ImpactLevel) -> Color {
        switch impact {
        case .low: return .gray
        case .medium: return .yellow
        case .high: return .red
        }
    }

    // MARK: - State Views

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.1)
            Text("Loading headlines...")
                .font(.publicaPlay(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Unable to load news")
                .font(.publicaPlay(size: 16))
                .foregroundStyle(.primary)
            Text(error)
                .font(.publicaPlay(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Button("Try Again") {
                Task { await viewModel.loadNews() }
            }
            .font(.publicaPlay(size: 14))
            .buttonStyle(.glass)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "newspaper")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No articles found")
                .font(.publicaPlay(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Shared Components

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.publicaPlay(size: 24))
            Spacer()
        }
    }
}

// MARK: - URL Identifiable Extension

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Aurora Gradient Background

/// Soft animated aurora glow that fills the inside of a card
struct AuroraGradientBorder: View {

    let cornerRadius: CGFloat
    @State private var rotation: Double = 0

    private let auroraColors: [Color] = [
        Color(red: 0.55, green: 0.45, blue: 0.75),
        Color(red: 0.40, green: 0.55, blue: 0.75),
        Color(red: 0.45, green: 0.65, blue: 0.70),
        Color(red: 0.60, green: 0.65, blue: 0.50),
        Color(red: 0.75, green: 0.60, blue: 0.45),
        Color(red: 0.70, green: 0.45, blue: 0.50),
        Color(red: 0.55, green: 0.45, blue: 0.75),
    ]

    var body: some View {
        ZStack {
            AngularGradient(
                colors: auroraColors,
                center: .center,
                angle: .degrees(rotation)
            )
            .blur(radius: 40)
            .opacity(0.3)
            .scaleEffect(1.15)

            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.background.opacity(0.7))

            AngularGradient(
                colors: auroraColors,
                center: .center,
                angle: .degrees(rotation)
            )
            .blur(radius: 30)
            .opacity(0.3)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}


#Preview {
    NewsView()
}
