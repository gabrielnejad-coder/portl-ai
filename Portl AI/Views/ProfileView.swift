import SwiftUI

/// Profile tab showing login info, wallet addresses, and settings
struct ProfileView: View {

    @State private var auth = AuthManager.shared
    @State private var wallet = WalletManager.shared
    @State private var theme = ThemeManager.shared
    @State private var showAdvanced = false
    @State private var copiedField: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    accountCard
                    walletsCard
                    appearanceCard
                    advancedSection
                    logoutButton
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .scrollEdgeEffectHidden(true, for: .all)
            .navigationTitle("Profile")
        }
    }

    // MARK: - Account Card

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.brandNavy.opacity(0.06))
                        .frame(width: 52, height: 52)
                    if auth.loginMethod == "Google" {
                        Image("GoogleLogo")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: loginIcon)
                            .font(.system(size: 22))
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Signed in with \(auth.loginMethod ?? "Unknown")")
                        .font(.publicaPlay(size: 16))

                    if let userId = auth.userId {
                        Text("ID: \(String(userId.prefix(12)))...")
                            .font(.publicaPlay(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private var loginIcon: String {
        switch auth.loginMethod {
        case "Apple": return "apple.logo"
        case "Google": return "g.circle.fill"
        case "Email": return "envelope.fill"
        default: return "person.circle"
        }
    }

    // MARK: - Wallets Card

    private var walletsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Embedded Wallets")
                .font(.publicaPlay(size: 14))
                .foregroundStyle(.secondary)

            if let sol = wallet.solanaAddress {
                walletRow(chain: "Solana", address: sol, icon: "s.circle.fill")
            }

            if let eth = wallet.ethereumAddress {
                walletRow(chain: "Ethereum", address: eth, icon: "e.circle.fill")
            }

            if wallet.solanaAddress == nil && wallet.ethereumAddress == nil {
                HStack {
                    ProgressView()
                        .tint(.secondary)
                    Text("Setting up wallets...")
                        .font(.publicaPlay(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private func walletRow(chain: String, address: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(chain)
                    .font(.publicaPlay(size: 14))
                Text(truncatedAddress(address))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                UIPasteboard.general.string = address
                copiedField = chain
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if copiedField == chain { copiedField = nil }
                }
            } label: {
                Text(copiedField == chain ? "Copied" : "Copy")
                    .font(.publicaPlay(size: 12))
                    .foregroundStyle(copiedField == chain ? .green : .secondary)
            }
            .buttonStyle(.haptic)
        }
    }

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        HStack {
            Image(systemName: theme.isDarkMode ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 18))
                .foregroundStyle(theme.isDarkMode ? .yellow : .orange)
                .frame(width: 24)

            Text("Dark Mode")
                .font(.publicaPlay(size: 15))

            Spacer()

            Toggle("", isOn: $theme.isDarkMode)
                .labelsHidden()
                .tint(.green)
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    showAdvanced.toggle()
                }
            } label: {
                HStack {
                    Text("Advanced")
                        .font(.publicaPlay(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .buttonStyle(.haptic)

            if showAdvanced {
                VStack(alignment: .leading, spacing: 12) {
                    if let sol = wallet.solanaAddress {
                        addressDetailRow(label: "Solana Address", value: sol)
                    }
                    if let eth = wallet.ethereumAddress {
                        addressDetailRow(label: "Ethereum Address", value: eth)
                    }
                    if let userId = auth.userId {
                        addressDetailRow(label: "Privy User ID", value: userId)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private func addressDetailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.publicaPlay(size: 11))
                .foregroundStyle(.secondary)

            HStack {
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    UIPasteboard.general.string = value
                    copiedField = label
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        if copiedField == label { copiedField = nil }
                    }
                } label: {
                    Image(systemName: copiedField == label ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(copiedField == label ? .green : .secondary)
                }
                .buttonStyle(.haptic)
            }
        }
    }

    // MARK: - Logout

    private var logoutButton: some View {
        Button {
            Task {
                wallet.reset()
                await auth.logout()
            }
        } label: {
            Text("Sign Out")
                .font(.publicaPlay(size: 16))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.haptic)
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}

#Preview {
    ProfileView()
}
