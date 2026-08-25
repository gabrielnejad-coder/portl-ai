import SwiftUI
import SafariServices

// MARK: - Safari View (UIViewControllerRepresentable)

/// Wraps SFSafariViewController for in-app browsing
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - AI Summary Generator

/// Generates an AI-powered summary for articles without source URLs
@MainActor @Observable
final class AISummaryGenerator {

    var summary: String = ""
    var isLoading = true

    static let openAIKey: String? = {
        // Check UserDefaults for stored key
        UserDefaults.standard.string(forKey: "openai_api_key")
    }()

    func generate(for article: NewsArticle) async {
        // If article has a description, use it as the base
        let description = article.description

        guard let apiKey = Self.openAIKey, !apiKey.isEmpty else {
            // No API key — fall back to description or a generated contextual summary
            if !description.isEmpty {
                summary = description
            } else {
                summary = generateLocalSummary(title: article.title, symbols: article.mentionedSymbols)
            }
            isLoading = false
            return
        }

        // Use OpenAI to expand the headline into a brief summary
        do {
            let service = AIService(apiKey: apiKey)
            let prompt = """
            Write a concise 2-3 paragraph news summary based on this headline and context. \
            Do not fabricate specific data, prices, or quotes. Focus on explaining what the \
            headline means and its potential implications. Write in a neutral, journalistic tone.

            Headline: \(article.title)
            \(description.isEmpty ? "" : "Context: \(description)")
            """
            let result = try await service.sendMessage(
                prompt,
                conversationHistory: []
            )
            summary = result
        } catch {
            // Fallback to description or local summary
            if !description.isEmpty {
                summary = description
            } else {
                summary = generateLocalSummary(title: article.title, symbols: article.mentionedSymbols)
            }
        }
        isLoading = false
    }

    /// Build a short contextual blurb from the headline when no API key and no description
    private func generateLocalSummary(title: String, symbols: [String]) -> String {
        var parts: [String] = []
        parts.append(title)
        if !symbols.isEmpty {
            let coins = symbols.joined(separator: ", ")
            parts.append("This article discusses developments related to \(coins) in the cryptocurrency market.")
        }
        parts.append("Tap the source link below for the full article.")
        return parts.joined(separator: "\n\n")
    }

    func cleanup() {
        // No resources to clean up
    }
}

// MARK: - Article Detail View

struct ArticleDetailView: View {

    let article: NewsArticle
    @State private var summaryGen = AISummaryGenerator()
    @State private var fontSize: CGFloat = 16
    @State private var scrollOffset: CGFloat = 0
    @State private var showSafari = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Estimated reading time in minutes
    private var readingTime: Int {
        let words = summaryGen.summary.split(separator: " ").count
        return max(1, words / 238)
    }

    /// Word count
    private var wordCount: Int {
        summaryGen.summary.split(separator: " ").count
    }

    /// Paragraphs split from summary text
    private var paragraphs: [String] {
        summaryGen.summary
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        Group {
            if article.hasURL {
                // Articles with URLs — open in SFSafariViewController immediately
                Color.clear
                    .onAppear { showSafari = true }
                    .fullScreenCover(isPresented: $showSafari, onDismiss: { dismiss() }) {
                        if let url = URL(string: article.articleURL!) {
                            SafariView(url: url)
                                .ignoresSafeArea()
                        }
                    }
            } else {
                // CryptoPanic articles without URLs — show AI summary
                summaryView
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !article.hasURL {
                    Button { dismiss() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back")
                                .font(.publicaPlay(size: 15))
                        }
                    }
                    .glassEffect(in: .capsule)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                if !article.hasURL {
                    HStack(spacing: 10) {
                        // Text size controls
                        if !summaryGen.summary.isEmpty {
                            Menu {
                                Button {
                                    withAnimation { fontSize = max(13, fontSize - 1) }
                                } label: {
                                    Label("Smaller Text", systemImage: "textformat.size.smaller")
                                }
                                Button {
                                    withAnimation { fontSize = 16 }
                                } label: {
                                    Label("Default Size", systemImage: "arrow.counterclockwise")
                                }
                                Button {
                                    withAnimation { fontSize = min(22, fontSize + 1) }
                                } label: {
                                    Label("Larger Text", systemImage: "textformat.size.larger")
                                }
                                Divider()
                                Button {
                                    UIPasteboard.general.string = summaryGen.summary
                                } label: {
                                    Label("Copy Summary", systemImage: "doc.on.doc")
                                }
                            } label: {
                                Image(systemName: "textformat.size")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .glassEffect(in: .circle)
                        }

                        ShareLink(item: article.title) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .glassEffect(in: .circle)
                    }
                }
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }

    // MARK: - Summary View (for articles without URLs)

    private var summaryView: some View {
        ZStack(alignment: .top) {
            // Reading progress bar
            if !summaryGen.isLoading && !summaryGen.summary.isEmpty {
                GeometryReader { geo in
                    let progress = min(1, max(0, scrollOffset / max(1, geo.size.height * 2)))
                    Rectangle()
                        .fill(Color.orange.opacity(0.6))
                        .frame(width: geo.size.width * progress, height: 2)
                        .animation(.smooth(duration: 0.15), value: progress)
                }
                .frame(height: 2)
                .zIndex(10)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Hero image for articles with coin icons
                    if article.hasImage, let urlStr = article.imageURL,
                       !article.mentionedSymbols.isEmpty {
                        HStack {
                            Spacer()
                            CryptoIconView(
                                imageURL: urlStr,
                                symbol: article.mentionedSymbols.first ?? "",
                                size: 64
                            )
                            Spacer()
                        }
                        .padding(.top, 8)
                    }

                    // Header
                    articleHeader

                    // Meta bar
                    if !summaryGen.isLoading && !summaryGen.summary.isEmpty {
                        metaBar
                    }

                    Rectangle()
                        .fill(Color.brandNavy.opacity(0.04))
                        .frame(height: 1)

                    // Body content
                    if summaryGen.isLoading {
                        loadingView
                    } else {
                        articleBody
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 60)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetKey.self,
                            value: -geo.frame(in: .named("articleScroll")).origin.y
                        )
                    }
                )
            }
            .coordinateSpace(name: "articleScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
        }
        .scrollEdgeEffectHidden(true, for: .all)
        .task {
            await summaryGen.generate(for: article)
        }
    }

    // MARK: - Header

    private var articleHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "newspaper")
                        .font(.system(size: 10, weight: .medium))
                    Text(article.source)
                        .font(.publicaPlay(size: 11))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.orange.opacity(0.12), in: Capsule())

                // Impact badge
                ImpactBadge(impact: article.impact, impactColor: impactColor)

                Spacer()

                Text(formattedDate)
                    .font(.publicaPlay(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text(article.title)
                .font(.publicaPlay(size: 24))
                .lineSpacing(4)

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.brandNavy.opacity(0.06))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text(String(article.source.prefix(1)).uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(article.source)
                        .font(.publicaPlay(size: 14))
                    Text(NewsViewModel.relativeTime(for: article.publishedDate))
                        .font(.publicaPlay(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Meta Bar

    private var metaBar: some View {
        HStack(spacing: 16) {
            Label("\(readingTime) min read", systemImage: "clock")
            Label("\(wordCount) words", systemImage: "text.word.spacing")

            Spacer()

            if AISummaryGenerator.openAIKey != nil {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("AI Summary")
                        .font(.publicaPlay(size: 10))
                }
                .foregroundStyle(.orange.opacity(0.7))
            }
        }
        .font(.publicaPlay(size: 12))
        .foregroundStyle(.secondary)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Generating summary...")
                .font(.publicaPlay(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Article Body

    private var articleBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.publicaPlay(size: fontSize))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineSpacing(6)
                    .padding(.bottom, 18)
            }
        }
    }

    // MARK: - Helpers

    private var impactColor: Color {
        switch article.impact {
        case .low: return .gray
        case .medium: return .yellow
        case .high: return .red
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: article.publishedDate)
    }
}

// MARK: - Impact Badge

/// Impact badge that shows a rotating aurora gradient background for high-impact articles
struct ImpactBadge: View {

    let impact: ImpactLevel
    let impactColor: Color
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
        HStack(spacing: 4) {
            Image(systemName: impact.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(impact.label)
                .font(.publicaPlay(size: 10))
        }
        .foregroundStyle(impact == .high ? .white : impactColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if impact == .high {
                Capsule()
                    .fill(.clear)
                    .background {
                        ZStack {
                            AngularGradient(
                                colors: auroraColors,
                                center: .center,
                                angle: .degrees(rotation)
                            )
                            .blur(radius: 8)
                            .opacity(0.7)

                            AngularGradient(
                                colors: auroraColors,
                                center: .center,
                                angle: .degrees(rotation + 60)
                            )
                            .blur(radius: 5)
                            .opacity(0.4)
                        }
                        .scaleEffect(1.5)
                    }
                    .clipShape(Capsule())
            } else {
                Capsule()
                    .fill(impactColor.opacity(0.12))
            }
        }
        .onAppear {
            if impact == .high {
                withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
    }
}

// MARK: - Scroll Offset Preference Key

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
