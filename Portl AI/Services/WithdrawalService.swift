import Foundation

/// Builds MoonPay off-ramp (sell) URLs for withdrawing crypto to a bank account.
/// Uses MoonPay's web widget URL which loads inside a WKWebView.
/// Docs: https://dev.moonpay.com/docs/ramps-sdk-sell-params
struct WithdrawalService {

    private static let moonPayAPIKey = "pk_live_syNBRNVCxtflsLCOOd6MLe9BVkHbele"
    private static let moonPaySellBaseURL = "https://sell.moonpay.com"

    /// Builds a MoonPay sell widget URL.
    /// - Parameters:
    ///   - baseCurrencyCode: The crypto to sell (e.g. "sol", "eth", "btc")
    ///   - refundWalletAddress: Wallet address for refunds if the sell fails
    ///   - quoteCurrencyCode: The fiat currency to receive (default "usd")
    ///   - quoteCurrencyAmount: Optional fiat amount the user wants to receive
    static func moonPaySellURL(
        baseCurrencyCode: String,
        refundWalletAddress: String,
        quoteCurrencyCode: String = "usd",
        quoteCurrencyAmount: Double? = nil
    ) -> URL? {
        var components = URLComponents(string: moonPaySellBaseURL)
        var queryItems = [
            URLQueryItem(name: "apiKey", value: moonPayAPIKey),
            URLQueryItem(name: "baseCurrencyCode", value: baseCurrencyCode.lowercased()),
            URLQueryItem(name: "quoteCurrencyCode", value: quoteCurrencyCode.lowercased()),
            URLQueryItem(name: "refundWalletAddress", value: refundWalletAddress),
            URLQueryItem(name: "colorCode", value: "4CAF50"),
            URLQueryItem(name: "theme", value: "dark"),
        ]

        if let amount = quoteCurrencyAmount, amount > 0 {
            queryItems.append(URLQueryItem(name: "quoteCurrencyAmount", value: String(format: "%.2f", amount)))
        }

        components?.queryItems = queryItems
        return components?.url
    }
}
