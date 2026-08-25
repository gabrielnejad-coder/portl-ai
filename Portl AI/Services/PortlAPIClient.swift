import Foundation

/// Client for the PortL analyst backend.
///
/// Replaces the on-device OpenAI integration. The provider key now lives on the
/// server, the model has tools to fetch live data instead of a pasted snapshot,
/// and requests are authenticated with the user's Privy access token — so a key
/// can no longer be read off the device, and usage is attributable per user.
struct PortlAPIClient {

    /// Backend base URL. Set PORTL_API_BASE_URL in the build settings per
    /// configuration so Debug can point at a local server.
    static let baseURL: URL = {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "PORTL_API_BASE_URL") as? String,
           let url = URL(string: configured), !configured.isEmpty {
            return url
        }
        return URL(string: "https://portl-backend.up.railway.app")!
    }()

    // MARK: - Wire types

    struct Turn: Encodable {
        let role: String
        let content: String
    }

    struct HoldingPayload: Encodable {
        let coinId: String
        let symbol: String
        let amount: Double
    }

    private struct ChatRequest: Encodable {
        let message: String
        let history: [Turn]
        let holdings: [HoldingPayload]
    }

    /// Events streamed back while the answer is produced.
    enum Event {
        /// A chunk of assistant text.
        case text(String)
        /// The model started a data lookup, e.g. "get_coin_chart".
        case toolStart(name: String)
        /// A lookup finished.
        case toolEnd(name: String, ok: Bool)
        /// Non-fatal notice (truncation, refusal, stale data).
        case warning(String)
        /// Terminal success.
        case done
    }

    enum ClientError: LocalizedError {
        case notAuthenticated
        case rateLimited
        case server(status: Int, message: String?)
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Please sign in again to use Portl."
            case .rateLimited:
                return "You're sending messages too quickly. Give it a moment."
            case .server(let status, let message):
                return message ?? "The assistant is unavailable right now (\(status))."
            case .transport(let detail):
                return detail
            }
        }
    }

    // MARK: - Streaming chat

    /// Streams a reply. The returned sequence finishes when the server sends
    /// `done`, and throws if the request fails or the server reports an error.
    static func streamChat(
        message: String,
        history: [Turn],
        holdings: [HoldingPayload],
        accessToken: String
    ) async throws -> AsyncThrowingStream<Event, Error> {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        // Generous: a tool-calling turn can legitimately take a while.
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(message: message, history: history, holdings: holdings)
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // Errors before the stream opens arrive as a normal JSON body.
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            let message = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["message"] as? String

            switch http.statusCode {
            case 401, 403: throw ClientError.notAuthenticated
            case 429: throw ClientError.rateLimited
            default: throw ClientError.server(status: http.statusCode, message: message)
            }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var eventName = "message"
                do {
                    for try await line in bytes.lines {
                        // Comment frames are keepalives.
                        if line.hasPrefix(":") { continue }

                        if line.hasPrefix("event:") {
                            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            continue
                        }

                        guard line.hasPrefix("data:") else {
                            // Blank line terminates an event; reset for the next.
                            if line.isEmpty { eventName = "message" }
                            continue
                        }

                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        switch eventName {
                        case "text":
                            if let delta = json["delta"] as? String {
                                continuation.yield(.text(delta))
                            }
                        case "tool_start":
                            if let name = json["name"] as? String {
                                continuation.yield(.toolStart(name: name))
                            }
                        case "tool_end":
                            if let name = json["name"] as? String {
                                continuation.yield(.toolEnd(name: name, ok: json["ok"] as? Bool ?? true))
                            }
                        case "warning":
                            if let m = json["message"] as? String {
                                continuation.yield(.warning(m))
                            }
                        case "error":
                            let m = json["message"] as? String ?? "The assistant hit an error."
                            continuation.finish(throwing: ClientError.transport(m))
                            return
                        case "done":
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        default:
                            break
                        }
                    }
                    // Stream ended without an explicit `done`.
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Friendly labels for the tool names the backend reports.
enum ToolLabel {
    static func describe(_ name: String) -> String {
        switch name {
        case "get_market_overview": return "Checking the market"
        case "get_coin_data": return "Looking up prices"
        case "get_coin_chart": return "Analyzing the chart"
        case "search_coins": return "Finding that coin"
        case "get_news": return "Reading the news"
        case "get_portfolio": return "Checking your wallet"
        default: return "Looking that up"
        }
    }
}
