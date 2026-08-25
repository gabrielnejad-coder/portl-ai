import Foundation
import PrivySDK

/// Centralized authentication manager wrapping Privy SDK
@MainActor @Observable
final class AuthManager {

    static let shared = AuthManager()

    // MARK: - State

    enum AuthState: Equatable {
        case loading
        case unauthenticated
        case authenticated
    }

    private(set) var state: AuthState = .loading
    private(set) var userId: String?
    private(set) var loginMethod: String?

    /// The Privy SDK instance — initialized once at app launch
    private(set) var privy: Privy!

    // MARK: - Email OTP flow state

    var emailOTPSent = false
    var emailForOTP = ""
    var authError: String?
    var isProcessing = false

    /// Set to true when a fresh login succeeds (not session restore)
    var showLoginSuccess = false

    /// Tracks whether the user actively initiated a login (vs session restore)
    private var loginInitiated = false

    // MARK: - Initialization

    private init() {}

    /// Call once at app startup. Must happen before any other Privy calls.
    func configure() {
        let config = PrivyConfig(
            appId: "cmmgig83e01nd0ci84srkxo22",
            appClientId: "client-WY6WtY1Fr95m5aNUcEkJHX9ysDYkcsVihMdQSdeKih8XR"
        )
        privy = PrivySdk.initialize(config: config)
        Task { await observeAuthState() }
    }

    /// Tracks whether we've seen an authenticated state at least once
    private var hasEverAuthenticated = false

    /// Listens for auth state changes from the SDK.
    /// The SDK may briefly emit `.unauthenticated` before restoring a
    /// persisted session from keychain, so we wait a short period before
    /// treating the first `.unauthenticated` emission as final.
    private func observeAuthState() async {
        for await authState in privy.authStateStream {
            switch authState {
            case .authenticated(let user):
                hasEverAuthenticated = true
                self.userId = user.id
                self.loginMethod = resolveLoginMethod(user)
                if loginInitiated {
                    showLoginSuccess = true
                    loginInitiated = false
                }
                self.state = .authenticated
            case .unauthenticated:
                // Always unblock login buttons when auth lands on unauthenticated,
                // even if the OAuth async call is still technically pending.
                isProcessing = false
                loginInitiated = false
                if !hasEverAuthenticated && self.state == .loading {
                    // SDK may not have finished restoring the session yet.
                    // Stay in loading briefly to give it time.
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        // If still unauthenticated after the delay, commit
                        if self.state == .loading {
                            self.userId = nil
                            self.loginMethod = nil
                            self.state = .unauthenticated
                        }
                    }
                } else {
                    self.userId = nil
                    self.loginMethod = nil
                    self.state = .unauthenticated
                }
            case .notReady:
                self.state = .loading
            default:
                break
            }
        }
    }

    // MARK: - Login Methods

    /// Sign in with Apple via OAuth
    func loginWithApple() async {
        isProcessing = true
        authError = nil
        loginInitiated = true
        do {
            let _ = try await privy.oAuth.login(with: .apple, appUrlScheme: "portlai")
        } catch {
            let desc = error.localizedDescription.lowercased()
            if !desc.contains("cancel") && !desc.contains("couldn't be completed") {
                authError = error.localizedDescription
            }
            loginInitiated = false
        }
        isProcessing = false
    }

    /// Sign in with Google via OAuth
    func loginWithGoogle() async {
        guard !isProcessing else { return }
        isProcessing = true
        authError = nil
        loginInitiated = true

        // Auto-unfreeze if Privy's server call hangs after OAuth completes
        let timeout = Task {
            try? await Task.sleep(for: .seconds(30))
            if isProcessing {
                isProcessing = false
                loginInitiated = false
            }
        }

        do {
            let _ = try await privy.oAuth.login(with: .google, appUrlScheme: "portlai")
        } catch {
            let desc = error.localizedDescription.lowercased()
            if !desc.contains("cancel") && !desc.contains("couldn't be completed") {
                authError = error.localizedDescription
            }
            loginInitiated = false
        }

        timeout.cancel()
        isProcessing = false
    }

    /// Step 1: Send OTP code to email
    func sendEmailCode(to email: String) async {
        isProcessing = true
        authError = nil
        do {
            try await privy.email.sendCode(to: email)
            emailForOTP = email
            emailOTPSent = true
        } catch {
            authError = error.localizedDescription
        }
        isProcessing = false
    }

    /// Step 2: Verify OTP code
    func verifyEmailCode(_ code: String) async {
        isProcessing = true
        authError = nil
        loginInitiated = true
        do {
            let _ = try await privy.email.loginWithCode(code, sentTo: emailForOTP)
        } catch {
            authError = error.localizedDescription
        }
        isProcessing = false
    }

    /// Sign out
    func logout() async {
        if let user = await privy.getUser() {
            await user.logout()
        }
        state = .unauthenticated
        userId = nil
        loginMethod = nil
    }

    // MARK: - Helpers

    private func resolveLoginMethod(_ user: PrivyUser) -> String {
        // Check linked accounts to determine the login method
        for account in user.linkedAccounts {
            if case .apple = account { return "Apple" }
            if case .google = account { return "Google" }
            if case .email = account { return "Email" }
        }
        return "Unknown"
    }

    /// Access the authenticated user's Privy user object
    func currentUser() async -> PrivyUser? {
        await privy?.getUser()
    }
}
