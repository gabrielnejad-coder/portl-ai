import Foundation
import PrivySDK

/// View model for AI chat.
///
/// The model now runs server-side with tool access, so this no longer gathers
/// market data or builds a context string — it sends the conversation and the
/// user's holdings, and renders what streams back.
@MainActor @Observable
final class ChatViewModel {

    var messages: [ChatMessage] = []
    var currentInput = ""
    var isLoading = false
    var errorMessage: String?
    var streamedResponse = ""

    /// What the assistant is doing right now, e.g. "Analyzing the chart".
    /// Nil when it is composing rather than fetching.
    var activity: String?

    /// Non-fatal notices from the backend (truncation, refusal).
    var notice: String?

    /// True once we have a Privy access token. Replaces the old
    /// `isConfigured` check for a user-supplied API key.
    var isReady = false

    private var streamTask: Task<Void, Never>?

    /// Keeps history bounded on the client too. The backend trims to a token
    /// budget as well, but there is no reason to upload turns it will discard.
    private static let maxHistoryTurns = 40

    // MARK: - Session

    func prepare() async {
        isReady = await AuthManager.shared.currentUser() != nil
        if !isReady {
            errorMessage = PortlAPIClient.ClientError.notAuthenticated.errorDescription
        }
    }

    // MARK: - Chat

    func sendMessage() async {
        let userMessage = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty, !isLoading else { return }

        guard let user = await AuthManager.shared.currentUser() else {
            errorMessage = PortlAPIClient.ClientError.notAuthenticated.errorDescription
            return
        }

        messages.append(ChatMessage(role: .user, content: userMessage))
        currentInput = ""
        isLoading = true
        errorMessage = nil
        notice = nil
        streamedResponse = ""
        activity = nil

        do {
            let token = try await user.getAccessToken()

            let history = messages
                .dropLast() // the message we just appended is sent separately
                .suffix(Self.maxHistoryTurns)
                .map { PortlAPIClient.Turn(role: $0.role == .user ? "user" : "assistant", content: $0.content) }

            let holdings = WalletManager.shared.tokenBalances.values.map {
                PortlAPIClient.HoldingPayload(coinId: $0.id, symbol: $0.symbol, amount: $0.amount)
            }

            let stream = try await PortlAPIClient.streamChat(
                message: userMessage,
                history: Array(history),
                holdings: holdings,
                accessToken: token
            )

            for try await event in stream {
                switch event {
                case .text(let delta):
                    activity = nil
                    streamedResponse += delta
                case .toolStart(let name):
                    activity = ToolLabel.describe(name)
                case .toolEnd:
                    activity = nil
                case .warning(let message):
                    notice = message
                case .done:
                    break
                }
            }

            commitStreamedResponse()
        } catch is CancellationError {
            // User navigated away or started a new message; keep what arrived.
            commitStreamedResponse()
        } catch {
            errorMessage = error.localizedDescription
            // Preserve a partial answer rather than discarding it. The previous
            // implementation dropped `streamedResponse` on error, which left the
            // user's question in history with no reply and corrupted the next turn.
            commitStreamedResponse()
        }

        activity = nil
        isLoading = false
    }

    /// Moves any streamed text into the transcript. Safe to call twice.
    private func commitStreamedResponse() {
        let text = streamedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        streamedResponse = ""
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(role: .assistant, content: text))
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
    }

    func clearChat() {
        cancel()
        messages.removeAll()
        streamedResponse = ""
        errorMessage = nil
        notice = nil
        activity = nil
        isLoading = false
    }
}
