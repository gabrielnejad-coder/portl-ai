import Foundation

/// View model for portfolio management
@Observable
final class PortfolioViewModel {

    var portfolio = Portfolio(holdings: [])
    var tradeHistory: [Trade] = []
    var currentPrices: [String: Double] = [:]
    var cryptoImages: [String: String] = [:]
    var isLoading = false
    var errorMessage: String?

    private let cryptoService = CryptoService.shared

    var totalValue: Double {
        portfolio.totalValue(prices: currentPrices)
    }

    var totalProfitLoss: Double {
        portfolio.totalProfitLoss(prices: currentPrices)
    }

    var totalProfitLossPercentage: Double {
        guard portfolio.totalInvested > 0 else { return 0 }
        return (totalProfitLoss / portfolio.totalInvested) * 100
    }

    func loadPortfolio() async {
        isLoading = true

        // Load sample data for demonstration
        if portfolio.holdings.isEmpty {
            portfolio.holdings = Self.sampleHoldings
        }

        // Fetch current prices for holdings
        do {
            let cryptos = try await cryptoService.fetchTopCryptos(limit: 50)
            for crypto in cryptos {
                currentPrices[crypto.id] = crypto.currentPrice
                if let url = crypto.imageURL {
                    cryptoImages[crypto.id] = url
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func executeTrade(_ trade: Trade) {
        tradeHistory.append(trade)

        if let index = portfolio.holdings.firstIndex(where: { $0.id == trade.cryptoId }) {
            switch trade.type {
            case .buy:
                let existing = portfolio.holdings[index]
                let newQuantity = existing.quantity + trade.quantity
                let newAvgPrice = (existing.totalInvested + trade.totalValue) / newQuantity
                portfolio.holdings[index] = Holding(
                    id: existing.id,
                    symbol: existing.symbol,
                    name: existing.name,
                    quantity: newQuantity,
                    averageBuyPrice: newAvgPrice
                )
            case .sell:
                portfolio.holdings[index] = Holding(
                    id: portfolio.holdings[index].id,
                    symbol: portfolio.holdings[index].symbol,
                    name: portfolio.holdings[index].name,
                    quantity: portfolio.holdings[index].quantity - trade.quantity,
                    averageBuyPrice: portfolio.holdings[index].averageBuyPrice
                )
                if portfolio.holdings[index].quantity <= 0 {
                    portfolio.holdings.remove(at: index)
                }
            }
        } else if trade.type == .buy {
            portfolio.holdings.append(Holding(
                id: trade.cryptoId,
                symbol: trade.symbol,
                name: trade.symbol.uppercased(),
                quantity: trade.quantity,
                averageBuyPrice: trade.pricePerUnit
            ))
        }
    }

    static let sampleHoldings: [Holding] = [
        Holding(id: "bitcoin", symbol: "btc", name: "Bitcoin", quantity: 0.5, averageBuyPrice: 42000),
        Holding(id: "ethereum", symbol: "eth", name: "Ethereum", quantity: 3.0, averageBuyPrice: 2200),
        Holding(id: "solana", symbol: "sol", name: "Solana", quantity: 25.0, averageBuyPrice: 95),
    ]
}
    