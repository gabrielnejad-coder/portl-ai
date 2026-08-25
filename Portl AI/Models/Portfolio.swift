import Foundation

/// Represents a user's holding of a specific cryptocurrency
struct Holding: Identifiable, Codable {
    let id: String
    let symbol: String
    let name: String
    var quantity: Double
    var averageBuyPrice: Double
    var imageURL: String?

    var totalInvested: Double {
        quantity * averageBuyPrice
    }

    func currentValue(at price: Double) -> Double {
        quantity * price
    }

    func profitLoss(at price: Double) -> Double {
        currentValue(at: price) - totalInvested
    }

    func profitLossPercentage(at price: Double) -> Double {
        guard totalInvested > 0 else { return 0 }
        return (profitLoss(at: price) / totalInvested) * 100
    }
}

/// Represents the user's overall portfolio
struct Portfolio {
    var holdings: [Holding]

    var totalInvested: Double {
        holdings.reduce(0) { $0 + $1.totalInvested }
    }

    func totalValue(prices: [String: Double]) -> Double {
        holdings.reduce(0) { total, holding in
            let price = prices[holding.id] ?? holding.averageBuyPrice
            return total + holding.currentValue(at: price)
        }
    }

    func totalProfitLoss(prices: [String: Double]) -> Double {
        totalValue(prices: prices) - totalInvested
    }
}
