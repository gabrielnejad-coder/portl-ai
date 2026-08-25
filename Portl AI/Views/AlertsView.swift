import SwiftUI

/// Model for a price alert
struct PriceAlert: Identifiable {
    let id = UUID()
    var coinName: String
    var symbol: String
    var targetPrice: Double
    var condition: Condition
    var isActive: Bool

    enum Condition: String, CaseIterable {
        case above = "Above"
        case below = "Below"
    }
}

/// Alerts tab for setting and managing price alerts
struct AlertsView: View {

    @State private var alerts: [PriceAlert] = Self.sampleAlerts
    @State private var showingNewAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    activeAlertsHeader
                    alertsList
                }
                .padding(.horizontal, 16)
            }
            .scrollEdgeEffectHidden(true, for: .all)
            .navigationTitle("Alerts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Alert", systemImage: "plus") {
                        showingNewAlert = true
                    }
                }
            }
            .sheet(isPresented: $showingNewAlert) {
                NewAlertSheet(alerts: $alerts)
            }
        }
    }

    // MARK: - Header

    private var activeAlertsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Active Alerts")
                    .font(.publicaPlay(size: 17))
                let activeCount = alerts.filter(\.isActive).count
                Text("\(activeCount) of \(alerts.count) alerts active")
                    .font(.publicaPlay(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.title2)
                .foregroundStyle(.orange)
        }
        .padding(12)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    // MARK: - Alerts List

    private var alertsList: some View {
        VStack(spacing: 10) {
            if alerts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No Alerts")
                        .font(.publicaPlay(size: 17))
                    Text("Tap + to create a price alert for any cryptocurrency.")
                        .font(.publicaPlay(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
                .glassEffect(in: .rect(cornerRadius: 16))
            } else {
                ForEach($alerts) { $alert in
                    AlertRow(alert: $alert, onDelete: {
                        alerts.removeAll { $0.id == alert.id }
                    })
                }
            }
        }
    }

    // MARK: - Sample Data

    static let sampleAlerts: [PriceAlert] = [
        PriceAlert(coinName: "Bitcoin", symbol: "BTC", targetPrice: 100_000, condition: .above, isActive: true),
        PriceAlert(coinName: "Ethereum", symbol: "ETH", targetPrice: 3_000, condition: .below, isActive: true),
        PriceAlert(coinName: "Solana", symbol: "SOL", targetPrice: 200, condition: .above, isActive: false),
        PriceAlert(coinName: "XRP", symbol: "XRP", targetPrice: 1.50, condition: .below, isActive: true),
    ]
}

// MARK: - Alert Row

struct AlertRow: View {

    @Binding var alert: PriceAlert
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Coin indicator
            Circle()
                .fill(alert.isActive ? Color.orange.opacity(0.2) : Color.gray.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(alert.symbol.prefix(2))
                        .font(.publicaPlay(size: 12))
                        .foregroundStyle(alert.isActive ? .orange : .secondary)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.coinName)
                    .font(.publicaPlay(size: 15))
                HStack(spacing: 4) {
                    Text(alert.condition.rawValue)
                        .font(.publicaPlay(size: 12))
                    PriceText(amount: alert.targetPrice, size: 12)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $alert.isActive)
                .labelsHidden()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.phantom)
            .foregroundStyle(.red.opacity(0.7))
        }
        .padding(12)
        .glassEffect(in: .rect(cornerRadius: 14))
        .opacity(alert.isActive ? 1 : 0.6)
    }
}

// MARK: - New Alert Sheet

struct NewAlertSheet: View {

    @Binding var alerts: [PriceAlert]
    @Environment(\.dismiss) private var dismiss

    @State private var coinName = "Bitcoin"
    @State private var symbol = "BTC"
    @State private var targetPrice = ""
    @State private var condition: PriceAlert.Condition = .above

    private let coins = [
        ("Bitcoin", "BTC"),
        ("Ethereum", "ETH"),
        ("Solana", "SOL"),
        ("Cardano", "ADA"),
        ("XRP", "XRP"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Cryptocurrency") {
                    Picker("Coin", selection: $coinName) {
                        ForEach(coins, id: \.0) { coin in
                            Text("\(coin.0) (\(coin.1))").tag(coin.0)
                        }
                    }
                    .onChange(of: coinName) { _, newValue in
                        symbol = coins.first { $0.0 == newValue }?.1 ?? ""
                    }
                }

                Section("Condition") {
                    Picker("When price is", selection: $condition) {
                        ForEach(PriceAlert.Condition.allCases, id: \.self) { cond in
                            Text(cond.rawValue).tag(cond)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Target Price (USD)", text: $targetPrice)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("New Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let price = Double(targetPrice) {
                            alerts.append(PriceAlert(
                                coinName: coinName,
                                symbol: symbol,
                                targetPrice: price,
                                condition: condition,
                                isActive: true
                            ))
                            dismiss()
                        }
                    }
                    .disabled(Double(targetPrice) == nil)
                }
            }
        }
    }
}

#Preview {
    AlertsView()
}
