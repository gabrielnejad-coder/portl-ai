import SwiftUI
import WebKit

/// Withdrawal flow: enter amount → process via MoonPay sell widget
struct WithdrawView: View {

    @State private var wallet = WalletManager.shared
    @State private var amountText = ""
    @State private var status: WithdrawalStatus = .idle
    @State private var showWebView = false
    @State private var webViewURL: URL?
    @Environment(\.dismiss) private var dismiss

    /// Available balance passed in from the dashboard
    let availableBalance: Double

    private var enteredAmount: Double {
        Double(amountText) ?? 0
    }

    private var isValidAmount: Bool {
        enteredAmount > 0 && enteredAmount <= availableBalance + 0.01
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    balanceHeader
                    amountEntry
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .scrollEdgeEffectHidden(true, for: .all)
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Withdraw to Bank")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.publicaPlay(size: 15))
                }
            }
            .sheet(isPresented: $showWebView) {
                if let url = webViewURL {
                    WithdrawWebViewSheet(url: url) {
                        status = .success
                        showWebView = false
                    }
                }
            }
            .overlay {
                if status == .success {
                    successOverlay
                }
            }
        }
    }

    // MARK: - Balance Header

    private var balanceHeader: some View {
        VStack(spacing: 6) {
            Text("Available Balance")
                .font(.publicaPlay(size: 13))
                .foregroundStyle(.secondary)

            Text(availableBalance.asCurrency)
                .font(.priceThin(size: 32))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Amount Entry

    private var amountEntry: some View {
        VStack(spacing: 20) {
            // Amount input
            VStack(spacing: 12) {
                Text("Amount (USD)")
                    .font(.publicaPlay(size: 13))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("$")
                        .font(.priceThin(size: 40))
                        .foregroundStyle(.primary.opacity(0.5))

                    TextField("0.00", text: $amountText)
                        .font(.priceThin(size: 40))
                        .foregroundStyle(.primary)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .tint(.green)
                }
                .frame(maxWidth: .infinity)

                // Quick amount buttons
                HStack(spacing: 10) {
                    quickAmountButton(label: "25%", fraction: 0.25)
                    quickAmountButton(label: "50%", fraction: 0.50)
                    quickAmountButton(label: "75%", fraction: 0.75)
                    quickAmountButton(label: "Max", fraction: 1.0)
                }
            }
            .padding(20)
            .glassEffect(in: .rect(cornerRadius: 16))

            // Fee estimate
            if enteredAmount > 0 {
                feeEstimate
            }

            // Info row
            HStack(spacing: 8) {
                Image(systemName: "building.columns")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("Processed by MoonPay · 1-3 business days")
                    .font(.publicaPlay(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Withdraw button
            Button {
                initiateWithdrawal()
            } label: {
                HStack(spacing: 8) {
                    if status == .processing {
                        ProgressView()
                            .tint(.black)
                    }
                    Text(status == .processing ? "Processing..." : "Withdraw \(enteredAmount > 0 ? enteredAmount.asCurrency : "")")
                        .font(.appSemibold(size: 16))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isValidAmount ? .green : .gray.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.haptic)
            .disabled(!isValidAmount || status == .processing)

            if case .failed(let message) = status {
                Text(message)
                    .font(.publicaPlay(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func quickAmountButton(label: String, fraction: Double) -> some View {
        Button {
            let amount = availableBalance * fraction
            amountText = String(format: "%.2f", amount)
        } label: {
            Text(label)
                .font(.publicaPlay(size: 13))
                .foregroundStyle(.primary.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .glassEffect(in: .capsule)
        }
        .buttonStyle(.phantom)
    }

    private var feeEstimate: some View {
        VStack(spacing: 8) {
            feeRow(label: "Network fee", value: "~$0.50")
            feeRow(label: "MoonPay fee", value: "~1.5%")
            Divider().overlay(Color.primary.opacity(0.06))
            let fee = enteredAmount * 0.015 + 0.50
            feeRow(label: "You receive", value: max(enteredAmount - fee, 0).asCurrency, highlight: true)
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 14))
    }

    private func feeRow(label: String, value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.publicaPlay(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.publicaPlay(size: 13))
                .foregroundStyle(highlight ? .white : .secondary)
        }
    }

    // MARK: - Withdrawal Logic

    private func initiateWithdrawal() {
        guard isValidAmount else { return }

        status = .processing

        let walletAddress = wallet.solanaAddress ?? wallet.ethereumAddress ?? ""

        if let url = WithdrawalService.moonPaySellURL(
            baseCurrencyCode: "sol",
            refundWalletAddress: walletAddress,
            quoteCurrencyAmount: enteredAmount
        ) {
            webViewURL = url
            showWebView = true
            status = .idle
        } else {
            status = .failed("Could not connect to MoonPay")
        }
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Withdrawal Initiated")
                .font(.appSemibold(size: 22))
                .foregroundStyle(.primary)

            Text("Your \(enteredAmount.asCurrency) withdrawal is being processed. Funds will arrive in your bank account in 1-3 business days.")
                .font(.publicaPlay(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.appSemibold(size: 16))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.haptic)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(0.97))
        .transition(.opacity)
    }
}

// MARK: - Withdraw WebView Sheet

struct WithdrawWebViewSheet: View {

    let url: URL
    var onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WithdrawWebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("MoonPay")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            onComplete()
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

/// WKWebView wrapper for the MoonPay sell widget
struct WithdrawWebView: UIViewRepresentable {

    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            .allow
        }
    }
}

#Preview {
    WithdrawView(availableBalance: 1234.56)
}
