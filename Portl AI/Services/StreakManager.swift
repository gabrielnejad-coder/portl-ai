import Foundation
import Observation

/// Tracks consecutive daily app opens and weekly check-in activity.
@Observable
final class StreakManager {

    static let shared = StreakManager()

    // MARK: - Public state

    /// Current consecutive-day streak
    private(set) var streakDays: Int = 0

    /// Dates the user checked in (stored as yyyy-MM-dd strings)
    private(set) var checkInDates: Set<String> = []

    /// Portfolio goal target (user-configurable)
    var portfolioGoal: Double {
        get { UserDefaults.standard.double(forKey: goalKey).nonZeroOrDefault(1000) }
        set { UserDefaults.standard.set(newValue, forKey: goalKey) }
    }

    // MARK: - Keys

    private let streakKey = "portl_streak_days"
    private let lastCheckInKey = "portl_last_checkin"
    private let checkInsKey = "portl_checkin_dates"
    private let goalKey = "portl_portfolio_goal"

    // MARK: - Init

    private init() {
        loadState()
        recordToday()
    }

    // MARK: - Public API

    /// Record today's check-in and update the streak.
    func recordToday() {
        let today = Self.dateString(from: .now)

        // Already checked in today
        guard !checkInDates.contains(today) else { return }

        checkInDates.insert(today)

        let yesterday = Self.dateString(from: Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        let lastCheckIn = UserDefaults.standard.string(forKey: lastCheckInKey) ?? ""

        if lastCheckIn == yesterday {
            // Consecutive day — increment streak
            streakDays += 1
        } else if lastCheckIn == today {
            // Same day, no change
        } else {
            // Streak broken — reset to 1
            streakDays = 1
        }

        UserDefaults.standard.set(today, forKey: lastCheckInKey)
        saveState()
    }

    /// Whether the user checked in on a specific date.
    func didCheckIn(on date: Date) -> Bool {
        checkInDates.contains(Self.dateString(from: date))
    }

    /// Returns the 7 dates for the current week (Mon–Sun).
    func currentWeekDates() -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        // Find Monday of this week
        let weekday = calendar.component(.weekday, from: today)
        // weekday: 1=Sun, 2=Mon, ..., 7=Sat
        let daysFromMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today)!

        return (0..<7).map { offset in
            calendar.date(byAdding: .day, value: offset, to: monday)!
        }
    }

    // MARK: - Persistence

    private func loadState() {
        streakDays = UserDefaults.standard.integer(forKey: streakKey)
        if streakDays == 0 { streakDays = 1 }

        if let saved = UserDefaults.standard.array(forKey: checkInsKey) as? [String] {
            checkInDates = Set(saved)
        }
    }

    private func saveState() {
        UserDefaults.standard.set(streakDays, forKey: streakKey)
        UserDefaults.standard.set(Array(checkInDates), forKey: checkInsKey)
    }

    // MARK: - Helpers

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dateString(from date: Date) -> String {
        formatter.string(from: date)
    }
}

private extension Double {
    func nonZeroOrDefault(_ fallback: Double) -> Double {
        self > 0 ? self : fallback
    }
}
