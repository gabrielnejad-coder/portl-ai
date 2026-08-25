import SwiftUI

// MARK: - Shimmer Modifier

/// Adds a subtle horizontal shimmer animation to any view
struct ShimmerModifier: ViewModifier {

    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color.brandNavy.opacity(0.08), location: 0.5),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: geo.size.width * phase)
                }
                .clipped()
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Skeleton Coin Row

/// Placeholder row matching CoinHoldingRow layout
struct SkeletonCoinRow: View {

    var body: some View {
        HStack(spacing: 14) {
            // Icon placeholder
            Circle()
                .fill(Color.brandNavy.opacity(0.06))
                .frame(width: 48, height: 48)

            // Name & price placeholders
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.brandNavy.opacity(0.06))
                    .frame(width: 60, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.brandNavy.opacity(0.04))
                    .frame(width: 80, height: 12)
            }

            Spacer()

            // Value placeholder
            VStack(alignment: .trailing, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.brandNavy.opacity(0.06))
                    .frame(width: 70, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.brandNavy.opacity(0.04))
                    .frame(width: 50, height: 12)
            }

            // Sparkline placeholder
            VStack(alignment: .trailing, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.brandNavy.opacity(0.04))
                    .frame(width: 56, height: 26)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.brandNavy.opacity(0.04))
                    .frame(width: 45, height: 12)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
        .shimmer()
    }
}

// MARK: - Skeleton Holdings List

/// Shows multiple skeleton rows to fill the holdings section
struct SkeletonHoldingsList: View {

    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonCoinRow()
                    .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Skeleton Market Row

/// Placeholder matching MarketRowView layout
struct SkeletonMarketRow: View {

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            Circle()
                .fill(Color.brandNavy.opacity(0.06))
                .frame(width: 52, height: 52)

            // Name & market cap
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.brandNavy.opacity(0.06))
                    .frame(width: 55, height: 16)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.brandNavy.opacity(0.04))
                    .frame(width: 80, height: 12)
            }

            Spacer()

            // Price & change
            VStack(alignment: .trailing, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.brandNavy.opacity(0.06))
                    .frame(width: 80, height: 16)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.brandNavy.opacity(0.04))
                    .frame(width: 55, height: 14)
            }
        }
        .shimmer()
    }
}

#Preview("Skeleton Coin Row") {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        VStack {
            SkeletonCoinRow()
            SkeletonCoinRow()
            SkeletonCoinRow()
        }
        .padding()
    }
}
