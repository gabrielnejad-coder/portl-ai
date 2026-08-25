import Foundation

// The on-device OpenAI integration that used to live here has been removed.
//
// It required each user to paste their own `sk-` key, which was stored in
// plaintext UserDefaults (and therefore backed up to iCloud), and it could only
// see a fixed snapshot of the top 15 coins pasted into the system prompt.
//
// The model now runs behind the PortL backend, which holds the provider key,
// authenticates requests with the user's Privy access token, and gives the
// model tools to fetch live prices, charts, news and wallet holdings on demand.
//
// See `PortlAPIClient` for the client and `backend/` for the service.
//
// The SwiftOpenAI package is no longer imported anywhere. It can be removed
// from the project's package dependencies in Xcode.

enum AIServiceError: LocalizedError {
    case emptyResponse
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Received an empty response from the assistant."
        case .notAuthenticated:
            return "Please sign in again to use Portl."
        }
    }
}
