import Foundation
import SwiftOpenAI

/// Service that wraps SwiftOpenAI for AI-powered trading insights
@Observable
final class AIService {

    private let openAIService: OpenAIService

    init(apiKey: String) {
        self.openAIService = OpenAIServiceFactory.service(apiKey: apiKey)
    }

    /// Sends a chat message and returns the assistant's response
    func sendMessage(
        _ message: String,
        conversationHistory: [ChatMessage],
        marketContext: String? = nil
    ) async throws -> String {
        var messages: [ChatCompletionParameters.Message] = [
            .init(
                role: .system,
                content: .text(Self.buildSystemPrompt(marketContext: marketContext))
            )
        ]

        // Add conversation history
        for chatMessage in conversationHistory {
            let role: ChatCompletionParameters.Message.Role = chatMessage.role == .user ? .user : .assistant
            messages.append(.init(role: role, content: .text(chatMessage.content)))
        }

        // Add the new user message
        messages.append(.init(role: .user, content: .text(message)))

        let parameters = ChatCompletionParameters(
            messages: messages,
            model: .gpt4o
        )

        let completion = try await openAIService.startChat(parameters: parameters)

        guard let responseContent = completion.choices.first?.message.content else {
            throw AIServiceError.emptyResponse
        }

        return responseContent
    }

    /// Streams a chat response
    func streamMessage(
        _ message: String,
        conversationHistory: [ChatMessage],
        marketContext: String? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        var messages: [ChatCompletionParameters.Message] = [
            .init(
                role: .system,
                content: .text(Self.buildSystemPrompt(marketContext: marketContext))
            )
        ]

        for chatMessage in conversationHistory {
            let role: ChatCompletionParameters.Message.Role = chatMessage.role == .user ? .user : .assistant
            messages.append(.init(role: role, content: .text(chatMessage.content)))
        }

        messages.append(.init(role: .user, content: .text(message)))

        let parameters = ChatCompletionParameters(
            messages: messages,
            model: .gpt4o
        )

        let stream = try await openAIService.startStreamedChat(parameters: parameters)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in stream {
                        if let content = chunk.choices.first?.delta.content {
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - System Prompt

    private static func buildSystemPrompt(marketContext: String?) -> String {
        var prompt = """
        You are Portl, an expert cryptocurrency market analyst built into the Portl trading app. \
        You have access to real-time market data and news headlines provided below. \
        Use this data to give specific, data-driven answers — reference actual prices, percentage changes, \
        and news events when relevant. Be concise but thorough.

        Guidelines:
        - When asked about a specific coin, cite its current price, 24h change, and any relevant news
        - When giving market analysis, reference the overall market direction (gainers vs losers ratio, avg change)
        - When asked for trade ideas, explain your reasoning using the data provided
        - Use bullet points and clear formatting for readability
        - If asked about coins not in the data, say so honestly
        - Always note that this is analysis, not financial advice
        """

        if let context = marketContext, !context.isEmpty {
            prompt += "\n\n" + context
        }

        return prompt
    }
}

enum AIServiceError: LocalizedError {
    case emptyResponse
    case invalidAPIKey

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Received an empty response from the AI service."
        case .invalidAPIKey:
            return "Invalid API key. Please check your OpenAI API key in Settings."
        }
    }
}
