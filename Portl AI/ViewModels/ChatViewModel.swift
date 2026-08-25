import Foundation

/// View model for AI chat interactions with live market context
@MainActor @Observable
final class ChatViewModel {

    var messages: [ChatMessage] = []
    var currentInput = ""
    var isLoading = false
    var errorMessage: String?
    var streamedResponse = ""

    /// Market data for context injection
    var cryptocurrencies: [Cryptocurrency] = []
    var newsArticles: [NewsArticle] = []
    var favoritedIds: Set<String> = []

    /// Whether market context has been loaded at least once
    var contextLoaded = false

    private var aiService: AIService?

    var isConfigured: Bool {
        aiService != nil
    }

    func configure(apiKey: String) {
        guard !apiKey.isEmpty else {
            aiService = nil
            return
        }
        aiService = AIService(apiKey: apiKey)
    }

    // MARK: - Market Context Loading

    /// Loads fresh market data and news for AI context
    func loadMarketContext() async {
        do {
            async let cryptoResult = CryptoService.shared.fetchTopCryptos(limit: 30)
            async let newsResult = NewsService.shared.fetchNews(filter: .all)

            let (cryptos, news) = try await (cryptoResult, newsResult)
            cryptocurrencies = cryptos
            newsArticles = news
            favoritedIds = FavoritesManager.shared.favoriteIds
            contextLoaded = true
        } catch {
            // Non-fatal — AI still works without context, just less informed
            if !contextLoaded {
                contextLoaded = true
            }
        }
    }

    /// Current market context string for injection into system prompt
    private var marketContextString: String? {
        guard !cryptocurrencies.isEmpty else { return nil }
        return MarketContext.buildContextString(
            cryptos: cryptocurrencies,
            news: newsArticles,
            favoritedIds: favoritedIds
        )
    }

    // MARK: - Chat

    func sendMessage() async {
        let userMessage = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        guard let aiService else {
            errorMessage = "Please set your OpenAI API key in Settings."
            return
        }

        let chatMessage = ChatMessage(role: .user, content: userMessage)
        messages.append(chatMessage)
        currentInput = ""
        isLoading = true
        errorMessage = nil
        streamedResponse = ""

        do {
            let stream = try await aiService.streamMessage(
                userMessage,
                conversationHistory: Array(messages.dropLast()),
                marketContext: marketContextString
            )

            for try await chunk in stream {
                streamedResponse += chunk
            }

            messages.append(ChatMessage(role: .assistant, content: streamedResponse))
            streamedResponse = ""
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func clearChat() {
        messages.removeAll()
        streamedResponse = ""
        errorMessage = nil
    }
}
