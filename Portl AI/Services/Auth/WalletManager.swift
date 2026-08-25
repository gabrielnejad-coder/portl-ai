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
        let id: String // CoinGecko coin id
        let mint: String
        let symbol: String
        /// Human-readable amount. Display only — never use this to build a
        /// transaction, because binary floating point cannot represent token
        /// amounts exactly.
        let amount: Double
        /// Base-unit amount exactly as the chain reports it. This is what a
        /// swap must be built from.
        let rawAmount: UInt64
        let decimals: Int
        let usdValue: Double
    }

    // MARK: - Solana token mints
    //
    // Verified SPL mints only. The previous version of this table also mapped
    // "bitcoin", "ethereum", "dogecoin" and "chainlink" to Sollet-era bridged
    // assets. Several of those bridges are dead, and routing real value to a
    // dead mint loses it, so those entries are gone. A coin that is not in
    // this table simply cannot be swapped in-app, which is the safe failure.
    //
    // Decimals are NOT assumed anywhere: they are read from the chain for
    // tokens the user actually holds. The values here are a fallback for
    // building the output side of a quote.
    private static let solanaTokenMints: [String: String] = [
        "solana": "So11111111111111111111111111111111111111112",
        "usd-coin": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
        "tether": "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
        "bonk": "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
        "jupiter-exchange-solana": "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN",
    ]

    /// Known decimals per mint, used only when the user holds no balance yet.
    private static let mintDecimals: [String: Int] = [
        "So11111111111111111111111111111111111111112": 9,
        "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v": 6,
        "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB": 6,
        "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263": 5,
        "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN": 6,
    ]

    static let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

    /// Solana RPC endpoint.
    ///
    /// The public `api.mainnet-beta.solana.com` node is heavily rate limited
    /// and not intended for production traffic — it will start returning 429s
    /// under real usage. Set SOLANA_RPC_URL in the build settings to a
    /// dedicated provider (Helius, Triton, QuickNode) before shipping.
    static let solanaRPCEndpoint: String = {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "SOLANA_RPC_URL") as? String,
           !configured.isEmpty {
            return configured
        }
        return "https://api.mainnet-beta.solana.com"
    }()

    /// Lamports reserved for rent and transaction fees, so a "sell max" of SOL
    /// cannot leave the account unable to pay for its own transaction.
    private static let solFeeReserveLamports: UInt64 = 10_000_000 // 0.01 SOL

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
            let lamports = try await fetchSOLBalance(address: address)
            tokenBalances["solana"] = TokenBalance(
                id: "solana",
                mint: Self.solanaTokenMints["solana"] ?? "",
                symbol: "SOL",
                amount: Double(lamports) / 1_000_000_000,
                rawAmount: lamports,
                decimals: 9,
                usdValue: 0 // filled in by refreshUSDValues(prices:)
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

    /// A priced, reviewable swap. Held so the user can confirm the actual
    /// exchange rate and worst-case output before anything is signed.
    struct SwapQuote {
        let inputMint: String
        let outputMint: String
        let inputRawAmount: UInt64
        let inputDecimals: Int
        let outAmountRaw: UInt64
        let outDecimals: Int
        let slippageBps: Int
        let priceImpactPct: Double
        /// Raw quote body, passed back to Jupiter verbatim when building the tx.
        let rawQuote: [String: Any]

        var inputAmount: Double { Self.toDouble(inputRawAmount, inputDecimals) }
        var expectedOutput: Double { Self.toDouble(outAmountRaw, outDecimals) }

        /// Worst acceptable output given the slippage tolerance. This is the
        /// number the user is really agreeing to.
        var minimumOutput: Double {
            expectedOutput * (1.0 - Double(slippageBps) / 10_000.0)
        }

        static func toDouble(_ raw: UInt64, _ decimals: Int) -> Double {
            Double(raw) / pow(10.0, Double(decimals))
        }
    }

    /// Converts a human-entered amount to base units without floating-point drift.
    /// Returns nil if the amount is not representable (negative, NaN, overflow).
    static func rawAmount(from amount: Decimal, decimals: Int) -> UInt64? {
        guard amount > 0, decimals >= 0, decimals <= 18 else { return nil }
        var scaled = amount * pow(Decimal(10), decimals)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .down)
        guard rounded > 0, rounded <= Decimal(UInt64.max) else { return nil }
        return UInt64(truncating: rounded as NSDecimalNumber)
    }

    /// Decimals for a mint: prefers what the chain reported for a held balance,
    /// falls back to the known table. Never guessed.
    func decimals(forMint mint: String) -> Int? {
        if let held = tokenBalances.values.first(where: { $0.mint == mint }) {
            return held.decimals
        }
        return Self.mintDecimals[mint]
    }

    private func validate(_ response: URLResponse, _ data: Data, step: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw WalletError.upstream("Jupiter \(step) failed (\(http.statusCode)): \(body)")
        }
    }

    /// Prices a swap without committing to it.
    func fetchSwapQuote(
        inputMint: String,
        outputMint: String = WalletManager.usdcMint,
        rawAmount: UInt64,
        slippageBps: Int = 50
    ) async throws -> SwapQuote {
        guard rawAmount > 0 else { throw WalletError.insufficientBalance }
        guard let inDecimals = decimals(forMint: inputMint),
              let outDecimals = decimals(forMint: outputMint) else {
            throw WalletError.unknownToken
        }

        var components = URLComponents(string: "https://quote-api.jup.ag/v6/quote")
        components?.queryItems = [
            URLQueryItem(name: "inputMint", value: inputMint),
            URLQueryItem(name: "outputMint", value: outputMint),
            URLQueryItem(name: "amount", value: String(rawAmount)),
            URLQueryItem(name: "slippageBps", value: String(slippageBps)),
        ]
        guard let url = components?.url else { throw WalletError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response, data, step: "quote")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WalletError.swapFailed
        }
        // Jupiter reports errors with HTTP 200 and an "error" key.
        if let error = json["error"] as? String {
            throw WalletError.upstream("No route: \(error)")
        }
        guard let outAmountString = json["outAmount"] as? String,
              let outAmount = UInt64(outAmountString) else {
            throw WalletError.swapFailed
        }

        let impact = Double(json["priceImpactPct"] as? String ?? "") ?? 0

        return SwapQuote(
            inputMint: inputMint,
            outputMint: outputMint,
            inputRawAmount: rawAmount,
            inputDecimals: inDecimals,
            outAmountRaw: outAmount,
            outDecimals: outDecimals,
            slippageBps: slippageBps,
            priceImpactPct: impact,
            rawQuote: json
        )
    }

    /// Builds, signs, and BROADCASTS the swap. Returns the transaction signature.
    ///
    /// The previous implementation called `signMessage(message:)`, which signs
    /// an arbitrary string and never submits anything to the network — so the
    /// swap silently never happened while the UI reported success. The correct
    /// call is `signAndSendTransaction(transaction:cluster:)`, which takes the
    /// decoded transaction bytes and broadcasts them.
    func executeSwap(quote: SwapQuote) async throws -> String {
        guard let user = await AuthManager.shared.currentUser(),
              let wallet = user.embeddedSolanaWallets.first else {
            throw WalletError.noWallet
        }

        let swapURL = URL(string: "https://quote-api.jup.ag/v6/swap")!
        var request = URLRequest(url: swapURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let body: [String: Any] = [
            "quoteResponse": quote.rawQuote,
            "userPublicKey": wallet.address,
            "wrapAndUnwrapSol": true,
            "dynamicComputeUnitLimit": true,
            "prioritizationFeeLamports": "auto",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data, step: "swap build")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WalletError.swapFailed
        }
        if let error = json["error"] as? String {
            throw WalletError.upstream("Swap build failed: \(error)")
        }
        guard let base64Tx = json["swapTransaction"] as? String,
              let txBytes = Data(base64Encoded: base64Tx) else {
            throw WalletError.swapFailed
        }

        return try await wallet.provider.signAndSendTransaction(
            transaction: txBytes,
            cluster: .mainnet,
            options: SolanaSendOptions(maxRetries: 3)
        )
    }

    /// Get the Solana mint address for a CoinGecko coin ID
    func solanaTokenMint(for coinId: String) -> String? {
        Self.solanaTokenMints[coinId]
    }

    /// Largest sellable base-unit amount, reserving SOL for transaction fees.
    func maxSellableRaw(for coinId: String) -> UInt64 {
        guard let balance = tokenBalances[coinId] else { return 0 }
        guard coinId == "solana" else { return balance.rawAmount }
        return balance.rawAmount > Self.solFeeReserveLamports
            ? balance.rawAmount - Self.solFeeReserveLamports
            : 0
    }

    // MARK: - Private Network Calls

    /// Returns the balance in lamports (base units), not SOL.
    private func fetchSOLBalance(address: String) async throws -> UInt64 {
        let json = try await rpcCall(method: "getBalance", params: [address])
        let result = json["result"] as? [String: Any]
        // Parse as UInt64: a Double loses precision above 2^53 lamports and
        // silently rounds balances.
        if let n = result?["value"] as? NSNumber { return n.uint64Value }
        return 0
    }

    /// Solana JSON-RPC call with status checking and an explicit timeout.
    private func rpcCall(method: String, params: [Any]) async throws -> [String: Any] {
        let url = URL(string: Self.solanaRPCEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WalletError.upstream("Solana RPC \(method) failed (\(http.statusCode))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WalletError.upstream("Solana RPC \(method) returned a malformed response")
        }
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "unknown error"
            throw WalletError.upstream("Solana RPC \(method): \(message)")
        }
        return json
    }

    private func fetchSPLTokenBalances(address: String) async throws -> [TokenBalance] {
        let json = try await rpcCall(
            method: "getTokenAccountsByOwner",
            params: [
                address,
                ["programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"],
                ["encoding": "jsonParsed"],
            ]
        )

        let result = json["result"] as? [String: Any]
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

            // Decimals come from the chain, per token. This is the fix for the
            // hardcoded 1e9 conversion, which was wrong for every 6-decimal
            // token (USDC, USDT) by a factor of 1000.
            guard let rawString = tokenAmount?["amount"] as? String,
                  let raw = UInt64(rawString),
                  let decimals = (tokenAmount?["decimals"] as? NSNumber)?.intValue,
                  raw > 0,
                  let coinId = mintToCoin[mint] else { continue }

            balances.append(TokenBalance(
                id: coinId,
                mint: mint,
                symbol: coinId.uppercased(),
                amount: Double(raw) / pow(10.0, Double(decimals)),
                rawAmount: raw,
                decimals: decimals,
                usdValue: 0
            ))
        }

        return balances
    }

    /// Fills in USD valuations from live prices. Previously `usdValue` was set
    /// to 0 with a comment promising it would be updated, and nothing ever did.
    func refreshUSDValues(prices: [String: Double]) {
        for (coinId, balance) in tokenBalances {
            guard let price = prices[coinId] else { continue }
            tokenBalances[coinId] = TokenBalance(
                id: balance.id,
                mint: balance.mint,
                symbol: balance.symbol,
                amount: balance.amount,
                rawAmount: balance.rawAmount,
                decimals: balance.decimals,
                usdValue: balance.amount * price
            )
        }
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
    case unknownToken
    case invalidAmount
    case upstream(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .swapFailed: return "The swap could not be completed."
        case .noWallet: return "No embedded wallet found"
        case .insufficientBalance: return "You don't have enough of that token."
        case .unknownToken: return "This token can't be swapped in the app yet."
        case .invalidAmount: return "Enter a valid amount."
        case .upstream(let message): return message
        }
    }
}
