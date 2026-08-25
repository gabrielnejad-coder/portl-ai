import Foundation

/// Represents a buy or sell trade action
struct Trade: Identifiable, Codable {
    let id: UUID
    let cryptoId: String
    let symbol: String
    let type: TradeType
    let quantity: Double
    let pricePerUnit: Double
    let timestamp: Date

    var totalValue: Double {
        quantity * pricePerUnit
    }

    enum TradeType: String, Codable {
        case buy
        case sell
    }
}


