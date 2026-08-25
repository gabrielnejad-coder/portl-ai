import SwiftUI
import CoreImage.CIFilterBuiltins

/// Main dashboard — clean minimalist layout: greeting, stats, coin cards
struct DashboardView: View {

    @State private var viewModel = MarketViewModel()
    @State private var showQR = false
    @State private var showWithdraw = false
    @State private var wallet = WalletManager.shared
    @State private var favorites = FavoritesManager.shared
    @State private var streak = StreakManager.shared
    @State private var auth = AuthManager.shared
    @State private var didInitialLoad = false
    @State private var revealed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    welcomeHeader
                    statCardsGrid
                    quickActions
                    coinCardsScroll
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 60)
            }
            .scrollEdgeEffectHidden(true, for: .all)
            .background {
                DashboardGradientBackground()
                    .ignoresSafeArea()
            }
            .task {
                await viewModel.loadMarketData()
                await viewModel.loadFavoritedCoins(favorites.favoriteIds)
                didInitialLoad = true
                viewModel.startPolling()
                viewModel.loadSparklinesIfNeeded()
                withAnimation(.spring(duration: 0.6, bounce: 0.15).delay(0.15)) {
                    revealed = true
                }
            }
            .onAppear {
                guard didInitialLoad else { return }
                viewModel.startPolling()
            }
            .onChange(of: favorites.favoriteIds) { _, newIds in
                Task {
                    await viewModel.loadFavoritedCoins(newIds)
                }
            }
            .refreshable {
                let w = wallet
                let vm = viewModel
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await w.refreshBalances() }
                    group.addTask { await vm.refresh() }
                }
            }
            .onDisappear {
                viewModel.stopPolling()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Cryptocurrency.self) { crypto in
                CryptoDetailView(crypto: crypto)
            }
            .sheet(isPresented: $showQR) {
                WalletQRSheet(wallet: wallet)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showWithdraw) {
                WithdrawView(availableBalance: totalPortfolioValue)
            }
        }
    }

    // MARK: - Welcome Header

    private var welcomeHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("WELCOME BACK")
                    .font(.publicaPlay(size: 11))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)

                Text("Hey, \(displayName) \u{1F44B}")
                    .font(.appSemibold(size: 24))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button {
                showQR = true
            } label: {
                Image(systemName: "qrcode")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.phantom)
            .glassEffect(in: .circle)
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 10)
    }

    // MARK: - Stat Cards Grid (2x2)

    private var statCardsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
        return LazyVGrid(columns: columns, spacing: 12) {
            statCard(
                label: "Portfolio",
                value: totalPortfolioValue.asCurrency,
                change: portfolioChange,
                icon: "chart.pie.fill"
            )
            statCard(
                label: "24h Change",
                value: formattedDayChange,
                change: dayChangePercent,
                icon: "chart.line.uptrend.xyaxis"
            )
            statCard(
                label: "Favorites",
                value: "\(favorites.favoriteIds.count)",
                change: nil,
                icon: "star.fill"
            )
            statCard(
                label: "Streak",
                value: "\(streak.streakDays) days",
                change: nil,
                icon: "flame.fill"
            )
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 14)
    }

    private func statCard(label: String, value: String, change: Double?, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(label)
                    .font(.publicaPlay(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.5))
            }

            Text(value)
                .font(.appSemibold(size: 22))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let change {
                HStack(spacing: 3) {
                    Image(systemName: change >= 0
                          ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 7))
                    Text("\(abs(change), specifier: "%.2f")%")
                        .font(.publicaPlay(size: 11))
                }
                .foregroundStyle(change >= 0 ? Color.atmPrimary : Color(red: 1.0, green: 0.35, blue: 0.35))
            } else {
                Text(" ")
                    .font(.publicaPlay(size: 11))
            }
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 12) {
            quickActionButton(icon: "plus", label: "Buy") {
                // navigate to buy
            }
            quickActionButton(icon: "arrow.up", label: "Send") {
                showWithdraw = true
            }
            quickActionButton(icon: "arrow.down", label: "Receive") {
                showQR = true
            }
            quickActionButton(icon: "arrow.left.arrow.right", label: "Swap") {
                // navigate to swap
            }
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 12)
        .animation(.spring(duration: 0.5, bounce: 0.12).delay(0.08), value: revealed)
    }

    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.atmPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.atmPrimary.opacity(0.12), in: Circle())
                Text(label)
                    .font(.publicaPlay(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.phantom)
    }

    // MARK: - Coin Cards (horizontal scroll)

    private var coinCardsScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Array(topCoins.enumerated()), id: \.element.id) { index, crypto in
                    NavigationLink(value: crypto) {
                        coinCard(crypto)
                    }
                    .buttonStyle(.phantom)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 18)
                    .animation(
                        .spring(duration: 0.5, bounce: 0.12).delay(0.12 + Double(index) * 0.07),
                        value: revealed
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func coinCard(_ crypto: Cryptocurrency) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Icon + name + change badge
            HStack(spacing: 10) {
                CryptoIconView(imageURL: crypto.imageURL, symbol: crypto.symbol, size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(crypto.name)
                        .font(.appMedium(size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(crypto.symbol.uppercased())
                        .font(.publicaPlay(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Text("\(crypto.priceChangePercentage24h >= 0 ? "+" : "")\(crypto.priceChangePercentage24h, specifier: "%.2f")%")
                    .font(.appMedium(size: 11))
                    .foregroundStyle(crypto.priceChangePercentage24h >= 0
                        ? Color.atmPrimary
                        : Color(red: 1.0, green: 0.35, blue: 0.35))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (crypto.priceChangePercentage24h >= 0
                            ? Color.atmPrimary
                            : Color(red: 1.0, green: 0.35, blue: 0.35)).opacity(0.12),
                        in: Capsule()
                    )
            }

            // Big price
            Text(crypto.currentPrice.asDollars)
                .font(.appSemibold(size: 28))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("Live Price \u{00B7} USD")
                .font(.publicaPlay(size: 11))
                .foregroundStyle(.secondary.opacity(0.7))

            // Sparkline
            if let sparkline = crypto.sparklineIn7d?.price, sparkline.count > 2 {
                MiniSparkline(
                    prices: sparkline,
                    isPositive: crypto.priceChangePercentage24h >= 0
                )
                .frame(height: 36)
                .padding(.vertical, 4)
            }

            // Bottom stats
            HStack(spacing: 0) {
                coinStat(label: "Market Cap", value: crypto.marketCap.asCompactMC)
                coinStat(label: "24h Volume", value: crypto.totalVolume.asCompactMC)
            }
        }
        .padding(18)
        .frame(width: 250)
        .glassEffect(in: .rect(cornerRadius: 18))
    }

    private func coinStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.publicaPlay(size: 10))
                .foregroundStyle(.secondary.opacity(0.7))
            Text(value)
                .font(.appMedium(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Computed Properties

    private var totalPortfolioValue: Double {
        var total = 0.0
        for crypto in viewModel.cryptocurrencies {
            let amount = wallet.balance(for: crypto.id)
            total += amount * crypto.currentPrice
        }
        return total
    }

    private var topCoins: [Cryptocurrency] {
        Array(viewModel.cryptocurrencies.prefix(3))
    }

    private var displayName: String {
        if let method = auth.loginMethod {
            switch method {
            case "Google", "Apple": return method + " User"
            case "Email": return "Trader"
            default: return "Trader"
            }
        }
        return "Trader"
    }

    private var portfolioChange: Double {
        let held = viewModel.cryptocurrencies.filter { wallet.balance(for: $0.id) > 0 }
        let source = held.isEmpty ? Array(viewModel.cryptocurrencies.prefix(5)) : held
        guard !source.isEmpty else { return 0 }
        return source.map(\.priceChangePercentage24h).reduce(0, +) / Double(source.count)
    }

    private var dayChangePercent: Double {
        portfolioChange
    }

    private var formattedDayChange: String {
        let change = portfolioChange
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", change))%"
    }
}

// MARK: - Portfolio Mini Sparkline

/// Thin white sparkline for the balance area — draws left-to-right on appear
private struct MiniPortfolioSparkline: View {

    let prices: [Double]
    let isPositive: Bool

    @State private var drawProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let sampled = downsample(prices, to: 40)
            let minVal = sampled.min() ?? 0
            let maxVal = sampled.max() ?? 1
            let range = max(maxVal - minVal, 0.0001)

            Path { path in
                for (index, price) in sampled.enumerated() {
                    let x = geo.size.width * CGFloat(index) / CGFloat(max(sampled.count - 1, 1))
                    let y = geo.size.height * (1 - CGFloat((price - minVal) / range))

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .trim(from: 0, to: drawProgress)
            .stroke(
                .primary.opacity(0.5),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            )
        }
        .onAppear {
            withAnimation(PhantomAnimation.chartDraw) {
                drawProgress = 1
            }
        }
    }

    private func downsample(_ data: [Double], to count: Int) -> [Double] {
        guard data.count > count else { return data }
        let step = Double(data.count) / Double(count)
        return (0..<count).map { i in
            data[min(Int(Double(i) * step), data.count - 1)]
        }
    }
}

// MARK: - Atmosphere Blue Gradient Background

/// Animated gradient background — atmosphere blue brand.
/// Dark: midnight (#060B14) base with subtle blue glow streaks.
/// Light: sky (#F4F8FF) base with soft blue washes.
struct DashboardGradientBackground: View {

    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            let t = phase
            let isDark = colorScheme == .dark

            // Base fill — deep midnight or clean sky
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(isDark ? .atmDarkBackground : .atmLightBackground)
            )

            // ── Primary glow — wide horizontal streak, center-upper ──
            let glowX = size.width * (0.50 + 0.04 * sin(t * 0.6))
            let glowY = size.height * (0.20 + 0.02 * cos(t * 0.5))
            let glowW = size.width * (1.3 + 0.08 * sin(t * 0.3))
            let glowH = size.height * (0.35 + 0.03 * cos(t * 0.4))

            let glowRect = CGRect(
                x: glowX - glowW / 2,
                y: glowY - glowH / 2,
                width: glowW,
                height: glowH
            )

            context.drawLayer { ctx in
                ctx.addFilter(.blur(radius: 70))
                if isDark {
                    // Bold atmosphere blue streak across upper canvas
                    ctx.fill(
                        Path(ellipseIn: glowRect),
                        with: .linearGradient(
                            Gradient(colors: [
                                Color.atmPrimary.opacity(0.65),
                                Color.atmGlow.opacity(0.35),
                                Color.atmPrimary.opacity(0.10),
                            ]),
                            startPoint: CGPoint(x: glowRect.midX, y: glowRect.minY),
                            endPoint: CGPoint(x: glowRect.midX, y: glowRect.maxY)
                        )
                    )
                } else {
                    // Rich sky-blue wash
                    ctx.fill(
                        Path(ellipseIn: glowRect),
                        with: .linearGradient(
                            Gradient(colors: [
                                Color.atmPrimary.opacity(0.22),
                                Color.atmSoftPrimary.opacity(0.55),
                                Color.atmLightAccent.opacity(0.20),
                            ]),
                            startPoint: CGPoint(x: glowRect.midX, y: glowRect.minY),
                            endPoint: CGPoint(x: glowRect.midX, y: glowRect.maxY)
                        )
                    )
                }
            }

            // ── Secondary highlight — upper-right vivid glow ──
            let hlX = size.width * (0.72 + 0.05 * cos(t * 0.7 + 1.0))
            let hlY = size.height * (0.10 + 0.02 * sin(t * 0.6))
            let hlSize = size.width * 0.45

            let hlRect = CGRect(
                x: hlX - hlSize / 2,
                y: hlY - hlSize / 2,
                width: hlSize,
                height: hlSize * 0.55
            )

            context.drawLayer { ctx in
                ctx.addFilter(.blur(radius: 50))
                ctx.fill(
                    Path(ellipseIn: hlRect),
                    with: .color(isDark
                        ? Color.atmGlow.opacity(0.30)
                        : Color.atmLightAccent.opacity(0.40))
                )
            }

            // ── Tertiary — lower-left glow pool (dark only) ──
            if isDark {
                let lX = size.width * (0.22 + 0.03 * sin(t * 0.5 + 2.0))
                let lY = size.height * (0.62 + 0.02 * cos(t * 0.4))
                let lW = size.width * 0.60
                let lH = size.height * 0.28

                let lRect = CGRect(
                    x: lX - lW / 2,
                    y: lY - lH / 2,
                    width: lW,
                    height: lH
                )

                context.drawLayer { ctx in
                    ctx.addFilter(.blur(radius: 60))
                    ctx.fill(
                        Path(ellipseIn: lRect),
                        with: .color(Color.atmPrimary.opacity(0.20))
                    )
                }
            }

            // ── Bottom vignette (dark only) — fades to pure midnight ──
            if isDark {
                context.drawLayer { ctx in
                    ctx.addFilter(.blur(radius: 25))
                    ctx.fill(
                        Path(CGRect(
                            origin: CGPoint(x: 0, y: size.height * 0.78),
                            size: CGSize(width: size.width, height: size.height * 0.22)
                        )),
                        with: .color(Color.atmDarkBackground.opacity(0.90))
                    )
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 25).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

/// Kept for backwards compatibility with NewsView
struct AuroraHeaderBackground: View {
    var body: some View {
        DashboardGradientBackground()
    }
}

// MARK: - Ambient Gradient Background (light variant — kept for reference)

struct AmbientGradientBackground: View {

    @State private var phase: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            let t = phase
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(red: 0.91, green: 0.90, blue: 0.88))
            )

            let tealX = size.width * (0.80 + 0.03 * sin(t * 0.4))
            let tealY = size.height * (0.02 + 0.02 * cos(t * 0.5))
            let tealW = size.width * 0.75
            let tealH = size.height * 0.30

            let tealRect = CGRect(
                x: tealX - tealW / 2,
                y: tealY - tealH / 2,
                width: tealW,
                height: tealH
            )

            context.drawLayer { ctx in
                ctx.addFilter(.blur(radius: 40))
                ctx.fill(
                    Path(ellipseIn: tealRect),
                    with: .color(Color(red: 0.12, green: 0.18, blue: 0.20))
                )
            }

            let blobX = size.width * (0.58 + 0.05 * sin(t * 0.7))
            let blobY = size.height * (0.22 + 0.03 * cos(t * 0.5))
            let blobW = size.width * (0.90 + 0.08 * sin(t * 0.3))
            let blobH = size.height * (0.38 + 0.04 * cos(t * 0.4))

            let blobRect = CGRect(
                x: blobX - blobW / 2,
                y: blobY - blobH / 2,
                width: blobW,
                height: blobH
            )

            context.drawLayer { ctx in
                ctx.addFilter(.blur(radius: 55))
                ctx.fill(
                    Path(ellipseIn: blobRect),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.90, green: 0.60, blue: 0.28),
                            Color(red: 0.85, green: 0.48, blue: 0.18),
                            Color(red: 0.72, green: 0.38, blue: 0.14),
                        ]),
                        startPoint: CGPoint(x: blobRect.minX, y: blobRect.midY),
                        endPoint: CGPoint(x: blobRect.maxX, y: blobRect.minY)
                    )
                )
            }

            let hlX = size.width * (0.52 + 0.06 * cos(t * 0.6 + 1.2))
            let hlY = size.height * (0.22 + 0.03 * sin(t * 0.8 + 0.5))
            let hlSize = size.width * (0.30 + 0.04 * sin(t * 0.5))

            let hlRect = CGRect(
                x: hlX - hlSize / 2,
                y: hlY - hlSize / 2,
                width: hlSize,
                height: hlSize * 0.8
            )

            context.drawLayer { ctx in
                ctx.addFilter(.blur(radius: 55))
                ctx.fill(
                    Path(ellipseIn: hlRect),
                    with: .color(Color(red: 0.93, green: 0.68, blue: 0.32).opacity(0.7))
                )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Coin Holding Row

struct CoinHoldingRow: View {

    let crypto: Cryptocurrency
    let holdingAmount: Double

    var body: some View {
        HStack(spacing: 14) {
            CryptoIconView(imageURL: crypto.imageURL, symbol: crypto.symbol, size: 48)

            VStack(alignment: .leading, spacing: 5) {
                Text(crypto.symbol.uppercased())
                    .font(.publicaPlay(size: 18))
                    .foregroundStyle(.primary)

                PriceText(amount: crypto.currentPrice, size: 13)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                if holdingAmount > 0 {
                    Text((holdingAmount * crypto.currentPrice).asCurrency)
                        .font(.publicaPlay(size: 17))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(formatHolding(holdingAmount, symbol: crypto.symbol))
                        .font(.publicaPlay(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(crypto.currentPrice.asDollars)
                        .font(.publicaPlay(size: 17))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(crypto.marketCap.asCompactMC)
                        .font(.publicaPlay(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 2) {
                Image(systemName: crypto.priceChangePercentage24h >= 0
                      ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 7))
                Text("\(abs(crypto.priceChangePercentage24h), specifier: "%.2f")%")
                    .font(.publicaPlay(size: 12))
            }
            .foregroundStyle(crypto.priceChangePercentage24h >= 0
                ? Color.atmPrimary
                : Color(red: 1.0, green: 0.35, blue: 0.35))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 14)
    }

    private func formatHolding(_ amount: Double, symbol: String) -> String {
        let sym = symbol.uppercased()
        if amount >= 1 {
            return String(format: "%.4f %@", amount, sym)
        } else {
            return String(format: "%.6f %@", amount, sym)
        }
    }
}

// MARK: - Mini Sparkline Chart

struct MiniSparkline: View {

    let prices: [Double]
    let isPositive: Bool

    @State private var drawProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let sampled = downsample(prices, to: 30)
            let minVal = sampled.min() ?? 0
            let maxVal = sampled.max() ?? 1
            let range = max(maxVal - minVal, 0.0001)

            Path { path in
                for (index, price) in sampled.enumerated() {
                    let x = geo.size.width * CGFloat(index) / CGFloat(sampled.count - 1)
                    let y = geo.size.height * (1 - CGFloat((price - minVal) / range))

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .trim(from: 0, to: drawProgress)
            .stroke(
                isPositive ? Color.atmPrimary : Color(red: 1.0, green: 0.35, blue: 0.35),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
        .onAppear {
            withAnimation(PhantomAnimation.chartDraw) {
                drawProgress = 1
            }
        }
    }

    private func downsample(_ data: [Double], to count: Int) -> [Double] {
        guard data.count > count else { return data }
        let step = Double(data.count) / Double(count)
        return (0..<count).map { i in
            data[min(Int(Double(i) * step), data.count - 1)]
        }
    }
}

// MARK: - Stretch-In Modifier

/// Animates a row sliding in from below with staggered timing — iOS-style entrance.
private struct StretchInModifier: ViewModifier {
    let index: Int
    var waitForReveal: Bool = false
    @State private var appeared = false

    private var delay: Double {
        Double(index) * 0.07
    }

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .scaleEffect(appeared ? 1 : 0.96, anchor: .top)
            .blur(radius: appeared ? 0 : 3)
            .onAppear {
                guard !waitForReveal else { return }
                withAnimation(.spring(duration: 0.5, bounce: 0.12).delay(delay)) {
                    appeared = true
                }
            }
            .onChange(of: waitForReveal) { _, waiting in
                if !waiting && !appeared {
                    withAnimation(.spring(duration: 0.5, bounce: 0.12).delay(0.1 + delay)) {
                        appeared = true
                    }
                }
            }
    }
}

// MARK: - Wallet QR Sheet

struct WalletQRSheet: View {

    let wallet: WalletManager
    @State private var selectedChain: Chain = .solana
    @State private var copiedField: String?
    @Environment(\.dismiss) private var dismiss

    enum Chain: String, CaseIterable, Identifiable {
        case solana = "Solana"
        case ethereum = "Ethereum"
        var id: String { rawValue }
    }

    private var qrAddress: String? {
        switch selectedChain {
        case .solana: return wallet.solanaAddress
        case .ethereum: return wallet.ethereumAddress
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            // Chain picker for QR code
            HStack(spacing: 8) {
                ForEach(Chain.allCases) { chain in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedChain = chain
                        }
                    } label: {
                        Text(chain.rawValue)
                            .font(.publicaPlay(size: 13))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .foregroundStyle(selectedChain == chain ? .white : .secondary)
                    }
                    .buttonStyle(.phantom)
                    .glassEffect(in: .capsule)
                    .opacity(selectedChain == chain ? 1.0 : 0.5)
                }
            }
            .padding(.top, 44)

            // QR code
            if let qrAddress {
                qrCodeImage(for: qrAddress)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(14)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            }

            // Address rows
            VStack(spacing: 12) {
                if let solAddress = wallet.solanaAddress {
                    addressRow(label: "Solana", address: solAddress, key: "sol")
                }
                if let ethAddress = wallet.ethereumAddress {
                    addressRow(label: "Ethereum", address: ethAddress, key: "eth")
                }
            }
            .padding(.horizontal, 4)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private func addressRow(label: String, address: String, key: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.publicaPlay(size: 12))
                    .foregroundStyle(.primary.opacity(0.5))

                Text(truncated(address))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.8))
            }

            Spacer()

            Button {
                UIPasteboard.general.string = address
                withAnimation(.snappy(duration: 0.2)) {
                    copiedField = key
                }
                // Reset after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.snappy(duration: 0.2)) {
                        if copiedField == key { copiedField = nil }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if copiedField == key {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.green)
                        Text("Copied")
                            .font(.publicaPlay(size: 11))
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.6))
                    }
                }
                .frame(width: 70)
            }
            .buttonStyle(.phantom)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(in: .rect(cornerRadius: 14))
    }

    private func truncated(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }

    /// Generate a QR code image from a string using CoreImage
    private func qrCodeImage(for string: String) -> Image {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return Image(systemName: "qrcode")
        }

        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return Image(systemName: "qrcode")
        }

        return Image(uiImage: UIImage(cgImage: cgImage))
    }
}

#Preview {
    DashboardView()
}
