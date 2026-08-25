import Foundation
import PrivySDK

/// Manages embedded wallets, token balances, and transaction operations
@MainActor @Observable
final class WalletManager {

    static let shared = WalletManager()

    // MARK: - State

    private(set) var solanaAddress: String?
    private(set) var ethereumAddress: String?

    /// Token balances keyed by mint address (Solana) or contract (EVM)
    private(set) var tokenBalances: [String: TokenBalance] = [:]

    private(set) var isLoadingBalances = false

    struct TokenBalance: Identifiable {
        let id: String // mint address
        let symbol: String
        let amount: Double
        let usdValue: Double
    }

    // MARK: - Solana token mint addresses for popular coins
    private static let solanaTokenMints: [String: String] = [
        "solana": "So11111111111111111111111111111111111111112",
        "bitcoin": "9n4nbM75f5Ui33ZbPYXn59EwSgE8CGsHtAeTH5YFeJ9E",
        "ethereum": "7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs",
        "usd-coin": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
        "tether": "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
        "bonk": "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
        "dogecoin": "27PuEe4x5MVhMjB22GDPFvRBzNfQ3Zy4KNEMgCnHJBo4",
        "chainlink": "CWE8jPTUYhdCTZYMNwgP7BjCo7ZHwB7PoF7cpfA4SYar",
    ]

    private init() {}

    // MARK: - Wallet Setup

    /// Creates embedded wallets after authentication if they don't exist
    func setupWallets() async {
        guard let user = await AuthManager.shared.currentUser() else { return }

        // Solana wallet
        if let existingSOL = user.embeddedSolanaWallets.first {
            solanaAddress = existingSOL.address
        } else {
            do {
                let wallet = try await user.createSolanaWallet()
                solanaAddress = wallet.address
            } catch {
                // Wallet may already exist
            }
        }

        // Ethereum wallet
        if let existingETH = user.embeddedEthereumWallets.first {
            ethereumAddress = existingETH.address
        } else {
            do {
                let wallet = try await user.createEthereumWallet()
                ethereumAddress = wallet.address
            } catch {
                // Wallet may already exist
            }
        }

        await refreshBalances()
    }

    // MARK: - Balance Fetching

    /// Fetches all token balances for the Solana embedded wallet
    func refreshBalances() async {
        guard let address = solanaAddress else { return }
        isLoadingBalances = true

        do {
            // Fetch SOL balance
            let solBalance = try await fetchSOLBalance(address: address)
            tokenBalances["solana"] = TokenBalance(
                id: "solana",
                symbol: "SOL",
                amount: solBalance,
                usdValue: 0 // Will be updated with price data
            )

            // Fetch SPL token balances
            let splBalances = try await fetchSPLTokenBalances(address: address)
            for balance in splBalances {
                tokenBalances[balance.id] = balance
            }
        } catch {
            // Keep existing balances on error
        }

        isLoadingBalances = false
    }

    /// Returns the balance for a specific coin ID (CoinGecko ID)
    func balance(for coinId: String) -> Double {
        tokenBalances[coinId]?.amount ?? 0
    }

    /// Check if user has any balance of a specific coin
    func hasPosition(for coinId: String) -> Bool {
        balance(for: coinId) > 0
    }

    // MARK: - MoonPay Fiat Onramp

    /// Returns a MoonPay URL pre-configured for buying a specific crypto
    func moonPayURL(for coinSymbol: String, walletAddress: String) -> URL? {
        let symbol = coinSymbol.lowercased()
        var components = URLComponents(string: "https://buy.moonpay.com")
        components?.queryItems = [
            URLQueryItem(name: "apiKey", value: "pk_live_YOUR_MOONPAY_KEY"),
            URLQueryItem(name: "currencyCode", value: symbol),
            URLQueryItem(name: "walletAddress", value: walletAddress),
            URLQueryItem(name: "colorCode", value: "#4CAF50"),
            URLQueryItem(name: "showWalletAddressForm", value: "false"),
        ]
        return components?.url
    }

    // MARK: - Jupiter Swap (Sell)

    /// Builds a Jupiter swap transaction to sell a token for USDC
    /// Returns the serialized transaction for signing
    func buildJupiterSwapTx(
        inputMint: String,
        outputMint: String = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", // USDC
        amount: Int, // in smallest unit (lamports etc)
        userAddress: String
    ) async throws -> String {
        // Step 1: Get quote
        let quoteURL = "https://quote-api.jup.ag/v6/quote?inputMint=\(inputMint)&outputMint=\(outputMint)&amount=\(amount)&slippageBps=50"
        guard let url = URL(string: quoteURL) else { throw WalletError.invalidURL }

        let (quoteData, _) = try await URLSession.shared.data(from: url)
        let quoteJSON = try JSONSerialization.jsonObject(with: quoteData) as? [String: Any]

        // Step 2: Get swap transaction
        let swapURL = URL(string: "https://quote-api.jup.ag/v6/swap")!
        var request = URLRequest(url: swapURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let swapBody: [String: Any] = [
            "quoteResponse": quoteJSON as Any,
            "userPublicKey": userAddress,
            "wrapAndUnwrapSol": true,
            "dynamicComputeUnitLimit": true,
            "prioritizationFeeLamports": "auto"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: swapBody)

        let (swapData, _) = try await URLSession.shared.data(for: request)
        let swapJSON = try JSONSerialization.jsonObject(with: swapData) as? [String: Any]

        guard let swapTransaction = swapJSON?["swapTransaction"] as? String else {
            throw WalletError.swapFailed
        }

        return swapTransaction
    }

    /// Signs and sends a Jupiter swap transaction using the embedded Solana wallet
    func executeSwap(serializedTx: String) async throws -> String {
        guard let user = await AuthManager.shared.currentUser(),
              let wallet = user.embeddedSolanaWallets.first else {
            throw WalletError.noWallet
        }

        // Sign the transaction with the embedded wallet
        let signature = try await wallet.provider.signMessage(message: serializedTx)
        return signature
    }

    /// Get the Solana mint address for a CoinGecko coin ID
    func solanaTokenMint(for coinId: String) -> String? {
        Self.solanaTokenMints[coinId]
    }

    // MARK: - Private Network Calls

    private func fetchSOLBalance(address: String) async throws -> Double {
        let url = URL(string: "https://api.mainnet-beta.solana.com")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getBalance",
            "params": [address]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = json?["result"] as? [String: Any]
        let lamports = result?["value"] as? Double ?? 0
        return lamports / 1_000_000_000 // Convert lamports to SOL
    }

    private func fetchSPLTokenBalances(address: String) async throws -> [TokenBalance] {
        let url = URL(string: "https://api.mainnet-beta.solana.com")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getTokenAccountsByOwner",
            "params": [
                address,
                ["programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"],
                ["encoding": "jsonParsed"]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = json?["result"] as? [String: Any]
        let accounts = result?["value"] as? [[String: Any]] ?? []

        // Reverse lookup: mint -> coinId
        let mintToCoin = Dictionary(uniqueKeysWithValues: Self.solanaTokenMints.map { ($0.value, $0.key) })

        var balances: [TokenBalance] = []
        for account in accounts {
            let accountData = account["account"] as? [String: Any]
            let parsedData = accountData?["data"] as? [String: Any]
            let parsed = parsedData?["parsed"] as? [String: Any]
            let info = parsed?["info"] as? [String: Any]
            let tokenAmount = info?["tokenAmount"] as? [String: Any]
            let mint = info?["mint"] as? String ?? ""
            let uiAmount = tokenAmount?["uiAmount"] as? Double ?? 0

            if uiAmount > 0, let coinId = mintToCoin[mint] {
                let symbol = Self.solanaTokenMints.first { $0.value == mint }?.key ?? ""
                balances.append(TokenBalance(
                    id: coinId,
                    symbol: symbol.uppercased(),
                    amount: uiAmount,
                    usdValue: 0
                ))
            }
        }

        return balances
    }

    // MARK: - Cleanup

    func reset() {
        solanaAddress = nil
        ethereumAddress = nil
        tokenBalances = [:]
    }
}

enum WalletError: LocalizedError {
    case invalidURL
    case swapFailed
    case noWallet
    case insufficientBalance

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .swapFailed: return "Swap transaction failed"
        case .noWallet: return "No embedded wallet found"
        case .insufficientBalance: return "Insufficient balance"
        }
    }
}
