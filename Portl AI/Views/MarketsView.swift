import SwiftUI

/// Row view for a cryptocurrency in the markets list.
/// When `showFavorite` is true, a star button appears on the right.
struct MarketRowView: View {

    let crypto: Cryptocurrency
    var showFavorite: Bool = false
    var showVerified: Bool = false

    private var favorites: FavoritesManager { FavoritesManager.shared }

    var body: some View {
        HStack(spacing: 14) {
            CryptoIconView(imageURL: crypto.imageURL, symbol: crypto.symbol, size: 52)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(crypto.symbol.uppercased())
                        .font(.publicaPlay(size: 20))
                    if showVerified {
                        Image("WavyCheck")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    }
                }
                if crypto.marketCap > 0 {
                    Text("\(crypto.marketCap.asCompactMC) MC")
                        .font(.publicaPlay(size: 14))
                        .foregroundStyle(.secondary)
                } else {
                    Text(crypto.name)
                        .font(.publicaPlay(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if crypto.currentPrice > 0 {
                VStack(alignment: .trailing, spacing: 5) {
                    PriceText(amount: crypto.currentPrice, size: 20)

                    HStack(spacing: 3) {
                        Image(systemName: crypto.priceChangePercentage24h >= 0
                              ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 10))
                        Text("\(abs(crypto.priceChangePercentage24h), specifier: "%.2f")%")
                            .font(.publicaPlay(size: 15))
                    }
                    .foregroundStyle(crypto.priceChangePercentage24h >= 0 ? .green : .red)
                }
            }

            if showFavorite {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        favorites.toggle(crypto.id)
                    }
                } label: {
                    Image(systemName: favorites.isFavorited(crypto.id) ? "star.fill" : "star")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(favorites.isFavorited(crypto.id) ? .yellow : .primary.opacity(0.3))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.haptic)
            }
        }
    }
}

#Preview {
    MarketRowView(crypto: Cryptocurrency(
        id: "bitcoin", symbol: "btc", name: "Bitcoin",
        currentPrice: 65000, priceChangePercentage24h: 2.5,
        marketCap: 1_270_000_000_000, totalVolume: 25_000_000_000,
        high24h: 66000, low24h: 63000, imageURL: nil
    ), showFavorite: true)
}
