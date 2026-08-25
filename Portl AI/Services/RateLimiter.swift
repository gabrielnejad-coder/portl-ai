import Foundation

/// Sliding-window rate limiter that enforces a maximum number of requests
/// per time window. Requests that would exceed the limit are queued and
/// executed once capacity becomes available.
actor RateLimiter {

    static let shared = RateLimiter(maxRequests: 29, window: 60)

    private let maxRequests: Int
    private let window: TimeInterval
    private var requestTimestamps: [Date] = []

    init(maxRequests: Int, window: TimeInterval) {
        self.maxRequests = maxRequests
        self.window = window
    }

    /// Waits until a request slot is available, then records the request.
    /// Call this before every network request.
    func acquire() async throws {
        while true {
            pruneOldTimestamps()

            if requestTimestamps.count < maxRequests {
                // Slot available — record and proceed
                requestTimestamps.append(Date())
                return
            }

            // Calculate how long until the oldest request falls outside the window
            guard let oldest = requestTimestamps.first else { return }
            let waitTime = window - Date().timeIntervalSince(oldest) + 0.1 // small buffer
            if waitTime > 0 {
                try await Task.sleep(for: .seconds(waitTime))
            }

            // After sleeping, check for cancellation
            try Task.checkCancellation()
        }
    }

    /// Removes timestamps older than the sliding window.
    private func pruneOldTimestamps() {
        let cutoff = Date().addingTimeInterval(-window)
        requestTimestamps.removeAll { $0 < cutoff }
    }

    /// Current number of requests in the window (for diagnostics).
    var currentCount: Int {
        var copy = requestTimestamps
        let cutoff = Date().addingTimeInterval(-window)
        copy.removeAll { $0 < cutoff }
        return copy.count
    }
}
