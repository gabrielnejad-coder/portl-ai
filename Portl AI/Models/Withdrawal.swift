import Foundation

/// Tracks the state of a withdrawal transaction
enum WithdrawalStatus: Equatable {
    case idle
    case processing
    case success
    case failed(String)
}
