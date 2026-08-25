import SwiftUI
import WebKit

/// Presents the MoonPay buy widget inside a WKWebView sheet.
/// Pass the coin's currency code (e.g. "sol", "eth") and the user's
/// Privy embedded wallet address so purchased crypto lands there.
struct MoonPayBuyView: UIViewRepresentable {

    let currencyCode: String
    let walletAddress: String
    var onDismiss: (() -> Void)?

    // MARK: - Configuration

    private static let apiKey = "pk_live_syNBRNVCxtflsLCOOd6MLe9BVkHbele"
    private static let baseURL = "https://buy.moonpay.com"

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        // Allow camera access for MoonPay KYC
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator

        // Build MoonPay URL
        var components = URLComponents(string: Self.baseURL)!
        components.queryItems = [
            URLQueryItem(name: "apiKey", value: Self.apiKey),
            URLQueryItem(name: "currencyCode", value: currencyCode.lowercased()),
            URLQueryItem(name: "walletAddress", value: walletAddress),
            URLQueryItem(name: "colorCode", value: "4CAF50"),
            URLQueryItem(name: "theme", value: "dark"),
            URLQueryItem(name: "showWalletAddressForm", value: "false"),
        ]

        if let url = components.url {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onDismiss: (() -> Void)?

        init(onDismiss: (() -> Void)?) {
            self.onDismiss = onDismiss
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            // Allow all navigation within the MoonPay widget
            .allow
        }
    }
}

/// SwiftUI wrapper that presents MoonPayBuyView inside a styled sheet
struct MoonPayBuySheet: View {

    let currencyCode: String
    let walletAddress: String
    @Environment(\.dismiss) private var dismiss
    var onComplete: (() -> Void)?

    var body: some View {
        NavigationStack {
            MoonPayBuyView(
                currencyCode: currencyCode,
                walletAddress: walletAddress,
                onDismiss: {
                    onComplete?()
                    dismiss()
                }
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Buy \(currencyCode.uppercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onComplete?()
                        dismiss()
                    }
                    .font(.publicaPlay(size: 15))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
