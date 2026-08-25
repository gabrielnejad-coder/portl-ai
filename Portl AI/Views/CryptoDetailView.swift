import SwiftUI
import Charts
import ActivityKit

/// Detail view for a cryptocurrency matching the reference design
struct CryptoDetailView: View {

    @State private var vm: CryptoDetailViewModel
    @State private var wallet = WalletManager.shared
    @State private var liveActivityManager = LiveActivityManager.shared
    @Environment(PortfolioViewModel.self) private var portfolioVM: PortfolioViewModel?
    @State private var showBuySheet = false
    @State private var showSellConfirm = false
    @State private var sellAmount = ""
    @State private var isSwapping = false
    @State private var swapError: String?
    @State private var pendingQuote: WalletManager.SwapQuote?
    @State private var showQuoteConfirm = false
    @State private var showSwapSuccess = false
    @State private var swapSignature: String?
    @State private var priceVisible = true
    @State private var safariURL: URL?

    init(crypto: Cryptocurrency) {
        _vm = State(initialValue: CryptoDetailViewModel(crypto: crypto))
    }

    /// Chart accent color — green if positive, orange if negative
    private var accentColor: Color {
        if let change = vm.rangeChangePercent {
            return change >= 0 ? .green : .orange
        }
        return .orange
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 0) {
                        headerSection
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .scrollTransition(topLeading: .interactive,
                                              bottomTrailing: .identity) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0)
                                    .blur(radius: phase.isIdentity ? 0 : 6)
                            }

                        priceSection
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .onScrollVisibilityChange { visible in
                                priceVisible = visible
                            }
                            .scrollTransition(topLeading: .interactive,
                                              bottomTrailing: .identity) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0)
                                    .blur(radius: phase.isIdentity ? 0 : 6)
                            }

                        chartSection
                            .padding(.top, 16)
                            .scrollTransition(topLeading: .interactive,
                                              bottomTrailing: .identity) { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0)
                                    .blur(radius: phase.isIdentity ? 0 : 4)
                            }

                        timeRangePicker
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        liveTrackingButton
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        buySellButtons
                            .padding(.horizontal, 16)
                            .padding(.top, 20)

                        walletPositionCard
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        relatedNewsSection
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 40)
                    }
                }
                .scrollEdgeEffectHidden(true, for: .all)

                // Sticky compact price — fades in when price section scrolls away
                compactPriceBar
                    .opacity(priceVisible ? 0 : 1)
                    .animation(.smooth(duration: 0.2), value: priceVisible)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 10) {
                    Button { vm.toggleFavorite() } label: {
                        Image(systemName: vm.isFavorited ? "star.fill" : "star")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(vm.isFavorited ? .yellow : .secondary)
                    }
                    .buttonStyle(.haptic)
                    .glassEffect(in: .circle)

                    ShareLink(item: "https://www.coingecko.com/en/coins/\(vm.crypto.id)") {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .glassEffect(in: .circle)
                }
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .task {
            // Load chart first (highest priority), then start live updates
            await vm.loadChart()
            vm.startLiveUpdates()
            // Load news in background — don't block the chart/price flow
            Task { await vm.loadRelatedNews() }
        }
        .onDisappear {
            vm.stopLiveUpdates()
        }
        .onChange(of: vm.selectedRange) {
            Task { await vm.loadChart() }
            vm.restartPollingIfNeeded()
        }
        .fullScreenCover(item: $safariURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }

    // MARK: - Header (icon + symbol + name)

    private var headerSection: some View {
        HStack(spacing: 12) {
            CryptoIconView(imageURL: vm.crypto.imageURL, symbol: vm.crypto.symbol, size: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.crypto.symbol.uppercased())
                    .font(.publicaPlay(size: 20))
                Text(vm.crypto.name)
                    .font(.publicaPlay(size: 14))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Market cap (top-right)
            VStack(alignment: .trailing, spacing: 2) {
                if vm.isLoadingPrice {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.brandNavy.opacity(0.06))
                        .frame(width: 80, height: 22)
                        .shimmer()
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(vm.crypto.marketCap.asCompactMC)
                            .font(.priceThin(size: 20))
                    }
                }

                Text("Market cap")
                    .font(.publicaPlay(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Price Section

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if vm.isLoadingPrice {
                // Placeholder shimmer while fetching real price
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.brandNavy.opacity(0.06))
                    .frame(width: 180, height: 36)
                    .shimmer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.brandNavy.opacity(0.04))
                    .frame(width: 120, height: 16)
                    .shimmer()
            } else {
                // Big price — disable animation during crosshair drag to prevent lag
                PriceText(amount: vm.displayPrice, size: 34)
                    .contentTransition(vm.inspectedPoint == nil ? .numericText() : .identity)
                    .animation(vm.inspectedPoint == nil ? .smooth(duration: 0.3) : .none, value: vm.displayPrice)

                // Change row
                if let dollarChange = vm.rangeChangeDollars,
                   let percentChange = vm.rangeChangePercent {
                    HStack(spacing: 6) {
                        Image(systemName: dollarChange >= 0
                              ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 10))

                        Text("\(abs(dollarChange).asDollars) (\(abs(percentChange), specifier: "%.2f")%)")
                            .font(.priceThin(size: 14))

                        Text(vm.selectedRange.changeLabel)
                            .font(.publicaPlay(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(accentColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Compact Price Bar (sticky header)

    private var compactPriceBar: some View {
        HStack(spacing: 8) {
            PriceText(amount: vm.isLoadingPrice ? 0 : vm.displayPrice, size: 17)
                .contentTransition(vm.inspectedPoint == nil ? .numericText() : .identity)

            if let percentChange = vm.rangeChangePercent, !vm.isLoadingPrice {
                HStack(spacing: 3) {
                    Image(systemName: percentChange >= 0
                          ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 6))
                    Text("\(abs(percentChange), specifier: "%.2f")%")
                        .font(.priceThin(size: 11))
                }
                .foregroundStyle(accentColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.top, 4)
        .allowsHitTesting(false)
    }

    // MARK: - Chart

    private let chartHeight: CGFloat = 220

    private let crosshairFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let crosshairEndFeedback = UIImpactFeedbackGenerator(style: .heavy)
    private let crosshairTickFeedback = UISelectionFeedbackGenerator()
    @State private var lastHapticX: CGFloat = 0

    /// Interpolates a price at the given date using binary search + linear interpolation.
    /// Returns a synthetic PriceDataPoint at the exact drag position for smooth crosshair movement.
    private func interpolatedPoint(at date: Date, in points: [PriceDataPoint]) -> PriceDataPoint? {
        guard points.count >= 2 else { return points.first }
        let target = date.timeIntervalSince1970

        // Clamp to data bounds
        if target <= points.first!.date.timeIntervalSince1970 {
            return points.first
        }
        if target >= points.last!.date.timeIntervalSince1970 {
            return points.last
        }

        // Binary search for the insertion point
        var lo = 0, hi = points.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].date.timeIntervalSince1970 < target {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        // lo is the first point >= target; interpolate between lo-1 and lo
        let before = points[lo - 1]
        let after = points[lo]
        let t1 = before.date.timeIntervalSince1970
        let t2 = after.date.timeIntervalSince1970
        let fraction = (t2 > t1) ? (target - t1) / (t2 - t1) : 0
        let interpolatedPrice = before.price + (after.price - before.price) * fraction

        return PriceDataPoint(date: date, price: interpolatedPrice)
    }

    private var chartSection: some View {
        let data = vm.filteredHistory
        let prices = data.map(\.price)
        let minP = prices.min() ?? 0
        let maxP = prices.max() ?? 1
        let hasDiff = maxP > minP
        // Use 5% of range as padding; fallback to 1% of price when range is zero
        let padding = hasDiff ? (maxP - minP) * 0.05 : max(maxP * 0.01, 0.0001)
        let yDomain = (minP - padding)...(maxP + padding)

        // Grid levels
        let yRange = yDomain.upperBound - yDomain.lowerBound
        let gridStep = yRange / 6.0
        let gridLevels = (1...5).map { yDomain.lowerBound + gridStep * Double($0) }

        return ZStack {
            if vm.isLoadingChart && data.isEmpty {
                ProgressView()
                    .frame(height: chartHeight)
                    .frame(maxWidth: .infinity)
            } else if vm.chartLoadFailed && data.isEmpty {
                // Chart failed to load — show retry option
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Chart unavailable")
                        .font(.publicaPlay(size: 14))
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await vm.loadChart() }
                    }
                    .font(.publicaPlay(size: 13))
                    .foregroundStyle(.primary)
                }
                .frame(height: chartHeight)
                .frame(maxWidth: .infinity)
            } else if data.count >= 2 {
                Chart {
                    // Dotted grid lines
                    ForEach(gridLevels, id: \.self) { level in
                        RuleMark(y: .value("Grid", level))
                            .foregroundStyle(.gray.opacity(0.10))
                            .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    }

                    // Price line
                    ForEach(data) { point in
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Price", point.price)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(accentColor)

                        AreaMark(
                            x: .value("Time", point.date),
                            yStart: .value("PriceStart", yDomain.lowerBound),
                            yEnd: .value("PriceEnd", point.price)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accentColor.opacity(0.4), accentColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: yDomain)
                // Crosshair overlay — rendered outside Chart body so the chart
                // doesn't re-render all marks on every drag frame.
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let plotFrame = geo[proxy.plotFrame!]

                        // Crosshair visuals (drawn as SwiftUI views, not chart marks)
                        if let inspected = vm.inspectedPoint,
                           let xPos = proxy.position(forX: inspected.date),
                           let yPos = proxy.position(forY: inspected.price) {
                            // Vertical dashed line
                            Path { path in
                                path.move(to: CGPoint(x: xPos, y: 0))
                                path.addLine(to: CGPoint(x: xPos, y: plotFrame.height))
                            }
                            .stroke(.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                            // Dot
                            Circle()
                                .fill(accentColor)
                                .frame(width: 10, height: 10)
                                .position(x: xPos, y: yPos)
                        }

                        // Gesture layer
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let wasNil = vm.inspectedPoint == nil
                                        let x = value.location.x
                                        guard let date: Date = proxy.value(atX: x) else { return }
                                        guard let point = interpolatedPoint(at: date, in: data) else { return }
                                        vm.inspectedPoint = point
                                        if wasNil {
                                            crosshairFeedback.impactOccurred()
                                            lastHapticX = x
                                        } else if abs(x - lastHapticX) > 12 {
                                            crosshairTickFeedback.selectionChanged()
                                            lastHapticX = x
                                        }
                                    }
                                    .onEnded { _ in
                                        crosshairEndFeedback.impactOccurred()
                                        vm.inspectedPoint = nil
                                    }
                            )
                    }
                }
                .padding(.horizontal, -16)
                .frame(height: chartHeight)
            } else if !vm.isLoadingChart {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No chart data")
                        .font(.publicaPlay(size: 14))
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await vm.loadChart() }
                    }
                    .font(.publicaPlay(size: 13))
                    .foregroundStyle(.primary)
                }
                .frame(height: chartHeight)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Time Range Picker

    private var timeRangePicker: some View {
        HStack(spacing: 0) {
            ForEach(ChartTimeRange.allCases) { range in
                Button {
                    vm.selectedRange = range
                } label: {
                    Text(range.rawValue)
                        .font(.publicaPlay(size: 13))
                        .foregroundStyle(vm.selectedRange == range ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if vm.selectedRange == range {
                                Capsule()
                                    .fill(Color.brandNavy.opacity(0.08))
                            }
                        }
                }
                .buttonStyle(.haptic)
            }


        }
    }

    // MARK: - Live Tracking Button

    private var liveTrackingButton: some View {
        let isTracking = liveActivityManager.isTrackingCoin(vm.crypto.id)

        return Button {
            if isTracking {
                liveActivityManager.stopTracking()
            } else {
                liveActivityManager.startTracking(crypto: vm.crypto)
            }
        } label: {
            HStack(spacing: 8) {
                if isTracking {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.red)
                    Text("Stop Live Tracking")
                        .font(.publicaPlay(size: 14))
                    Spacer()
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .modifier(PulseModifier())
                } else {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 15))
                        .foregroundStyle(.green)
                    Text("Track Price Live")
                        .font(.publicaPlay(size: 14))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.haptic)
        .foregroundStyle(.primary)
        .glassEffect(in: .capsule)
    }

    // MARK: - Buy / Sell Buttons

    private var buySellButtons: some View {
        HStack(spacing: 12) {
            // Buy button — opens MoonPay in-app sheet
            Button {
                showBuySheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("Buy")
                        .font(.publicaPlay(size: 15))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.haptic)
            .foregroundStyle(.primary)
            .glassEffect(in: .capsule)

            // Sell button — Jupiter swap to USDC
            Button {
                showSellConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14))
                    Text("Sell")
                        .font(.publicaPlay(size: 15))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.haptic)
            .foregroundStyle(.primary)
            .glassEffect(in: .capsule)
            .disabled(wallet.balance(for: vm.crypto.id) <= 0)
            .opacity(wallet.balance(for: vm.crypto.id) > 0 ? 1 : 0.4)
        }
        // Step 1 — enter an amount. This only fetches a price; nothing is signed.
        .alert("Sell \(vm.crypto.symbol.uppercased())", isPresented: $showSellConfirm) {
            TextField("Amount", text: $sellAmount)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) { sellAmount = "" }
            Button("Review") {
                Task { await requestQuote() }
            }
        } message: {
            let bal = wallet.balance(for: vm.crypto.id)
            Text("You have \(bal, specifier: "%.6f") \(vm.crypto.symbol.uppercased()).\nEnter an amount to quote a swap to USDC via Jupiter.")
        }
        // Step 2 — confirm the actual price. The user is agreeing to a rate,
        // not just an amount; previously they never saw one before signing.
        .alert("Confirm swap", isPresented: $showQuoteConfirm) {
            Button("Cancel", role: .cancel) { pendingQuote = nil; sellAmount = "" }
            Button("Swap") {
                Task { await confirmSwap() }
            }
        } message: {
            if let q = pendingQuote {
                Text("""
                Sell \(q.inputAmount, specifier: "%.6f") \(vm.crypto.symbol.uppercased())
                Receive about \(q.expectedOutput, specifier: "%.2f") USDC
                Minimum after \(Double(q.slippageBps) / 100, specifier: "%.2f")% slippage: \(q.minimumOutput, specifier: "%.2f") USDC
                Price impact: \(q.priceImpactPct * 100, specifier: "%.2f")%
                """)
            }
        }
        .alert("Swap submitted", isPresented: $showSwapSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Signature: \(swapSignature ?? "—")\nBalances update once the network confirms it.")
        }
        .sheet(isPresented: $showBuySheet) {
            MoonPayBuySheet(
                currencyCode: vm.crypto.symbol,
                walletAddress: wallet.solanaAddress ?? "",
                onComplete: {
                    Task { await wallet.refreshBalances() }
                }
            )
        }
    }

    /// Step 1: validate the amount against the real balance and price the swap.
    private func requestQuote() async {
        swapError = nil

        guard let mint = wallet.solanaTokenMint(for: vm.crypto.id) else {
            swapError = WalletError.unknownToken.errorDescription
            return
        }
        guard wallet.solanaAddress != nil else {
            swapError = WalletError.noWallet.errorDescription
            return
        }
        // Parse as Decimal, not Double: the amount is converted to integer base
        // units and binary floating point cannot represent decimal fractions
        // exactly.
        guard let typed = Decimal(string: sellAmount.trimmingCharacters(in: .whitespaces)),
              typed > 0,
              let decimals = wallet.decimals(forMint: mint),
              let raw = WalletManager.rawAmount(from: typed, decimals: decimals) else {
            swapError = WalletError.invalidAmount.errorDescription
            return
        }

        // The old code never checked this, so it would happily build a swap for
        // more than the wallet held and fail on-chain after the user confirmed.
        let sellable = wallet.maxSellableRaw(for: vm.crypto.id)
        guard raw <= sellable else {
            swapError = vm.crypto.id == "solana"
                ? "Not enough SOL — some must stay behind to cover network fees."
                : WalletError.insufficientBalance.errorDescription
            return
        }

        isSwapping = true
        do {
            pendingQuote = try await wallet.fetchSwapQuote(inputMint: mint, rawAmount: raw)
            showQuoteConfirm = true
        } catch {
            swapError = error.localizedDescription
        }
        isSwapping = false
    }

    /// Step 2: sign and broadcast the quote the user just approved.
    private func confirmSwap() async {
        guard let quote = pendingQuote else { return }

        isSwapping = true
        swapError = nil

        do {
            let signature = try await wallet.executeSwap(quote: quote)
            swapSignature = signature
            showSwapSuccess = true
            sellAmount = ""
            pendingQuote = nil
            // Only refresh after a real signature comes back. The previous code
            // refreshed unconditionally and reported success for a swap that
            // was never broadcast.
            await wallet.refreshBalances()
        } catch {
            swapError = error.localizedDescription
        }

        isSwapping = false
    }

    // MARK: - Wallet Position Card

    /// Shows the user's real wallet holding for this coin — hidden if no balance
    @ViewBuilder
    private var walletPositionCard: some View {
        let balance = wallet.balance(for: vm.crypto.id)
        if balance > 0 {
            let usdValue = balance * vm.crypto.currentPrice

            VStack(alignment: .leading, spacing: 12) {
                Text("Your Position")
                    .font(.publicaPlay(size: 14))
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(balance, specifier: "%.6f") \(vm.crypto.symbol.uppercased())")
                            .font(.priceThin(size: 16))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(usdValue.asCurrency)
                            .font(.priceThin(size: 16))
                    }
                }
            }
            .padding(14)
            .glassEffect(in: .rect(cornerRadius: 14))
        }
    }

    // MARK: - Related News

    @ViewBuilder
    private var relatedNewsSection: some View {
        if !vm.relatedNews.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Related News")
                    .font(.publicaPlay(size: 14))
                    .foregroundStyle(.secondary)

                // Featured top article with aurora gradient
                if let featured = vm.relatedNews.first {
                    featuredNewsCard(featured)
                }

                // Remaining articles
                ForEach(Array(vm.relatedNews.dropFirst())) { article in
                    newsRow(article)
                }
            }
        }
    }

    private func featuredNewsCard(_ article: NewsArticle) -> some View {
        Button {
            if let urlStr = article.articleURL, let url = URL(string: urlStr) {
                safariURL = url
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Impact + time header
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: article.impact.icon)
                            .font(.system(size: 9, weight: .semibold))
                        Text(article.impact.label)
                            .font(.publicaPlay(size: 10))
                    }
                    .foregroundStyle(impactColor(article.impact))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(impactColor(article.impact).opacity(0.12), in: Capsule())

                    Spacer()

                    Text(NewsViewModel.relativeTime(for: article.publishedDate))
                        .font(.publicaPlay(size: 11))
                        .foregroundStyle(.secondary)
                }

                // Title
                Text(article.title)
                    .font(.publicaPlay(size: 18))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)

                // Source footer
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.brandNavy.opacity(0.08))
                        .frame(width: 20, height: 20)
                        .overlay {
                            Text(String(article.source.prefix(1)).uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.primary.opacity(0.7))
                        }
                    Text(article.source)
                        .font(.publicaPlay(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
            .padding(16)
            .background {
                AuroraGradientBorder(cornerRadius: 18)
            }
        }
        .buttonStyle(.phantom)
    }

    private func newsRow(_ article: NewsArticle) -> some View {
        Button {
            if let urlStr = article.articleURL, let url = URL(string: urlStr) {
                safariURL = url
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Impact indicator
                Circle()
                    .fill(impactColor(article.impact))
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.publicaPlay(size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        Text(article.source)
                            .font(.publicaPlay(size: 11))
                            .foregroundStyle(.secondary)

                        Text("·")
                            .foregroundStyle(.primary.opacity(0.2))

                        Text(NewsViewModel.relativeTime(for: article.publishedDate))
                            .font(.publicaPlay(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .glassEffect(in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.phantom)
    }

    private func impactColor(_ impact: ImpactLevel) -> Color {
        switch impact {
        case .low: return .gray
        case .medium: return .yellow
        case .high: return .red
        }
    }

}

// MARK: - Pulse Animation Modifier

private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.6 : 1.0)
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

#Preview {
    NavigationStack {
        CryptoDetailView(crypto: Cryptocurrency(
            id: "bitcoin", symbol: "btc", name: "Bitcoin",
            currentPrice: 65000, priceChangePercentage24h: 2.5,
            marketCap: 1_270_000_000_000, totalVolume: 25_000_000_000,
            high24h: 66000, low24h: 63000, imageURL: nil
        ))
    }
    .preferredColorScheme(.light)
}
