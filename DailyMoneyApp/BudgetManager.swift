import Foundation
import Combine

final class BudgetManager: ObservableObject {
    static let defaultMonthlyAmount: Double = 120000
    private let roundingStep: Double = 500

    private enum Keys {
        static let monthlyAmount = "monthly_amount"
        static let dailyBudget = "daily_budget"
        static let dailyBudgetDate = "daily_budget_date"
        static let lastMonthlyAmountForBudget = "last_monthly_amount_for_budget"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var monthlyAmount: Double {
        let saved = defaults.double(forKey: Keys.monthlyAmount)
        return saved > 0 ? saved : Self.defaultMonthlyAmount
    }

    func remainingUntilEndOfMonth(monthSpent: Double) -> Double {
        monthlyAmount - monthSpent
    }

    func availableAmount(monthSpent: Double, todaySpent: Double) -> Double {
        dailyBudget(monthSpent: monthSpent) - todaySpent
    }

    /// Дневной бюджет: кэш на календарный день, иначе пересчёт от остатка месяца.
    func dailyBudget(monthSpent: Double, now: Date = Date()) -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let lastCalculationDate = defaults.object(forKey: Keys.dailyBudgetDate) as? Date
        let lastMonthlyAmount = defaults.double(forKey: Keys.lastMonthlyAmountForBudget)
        let currentMonthly = monthlyAmount

        let shouldRecalculate: Bool
        if let lastDate = lastCalculationDate {
            let lastDateDay = calendar.startOfDay(for: lastDate)
            if lastDateDay < today {
                shouldRecalculate = true
            } else if abs(lastMonthlyAmount - currentMonthly) > 0.01 {
                shouldRecalculate = true
            } else {
                shouldRecalculate = false
            }
        } else {
            shouldRecalculate = true
        }

        guard shouldRecalculate else {
            let savedBudget = defaults.double(forKey: Keys.dailyBudget)
            return savedBudget > 0 ? savedBudget : 0
        }

        let remainingBudget = currentMonthly - monthSpent
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
        let endOfMonthDay = calendar.startOfDay(for: endOfMonth)
        let daysRemaining = calendar.dateComponents([.day], from: today, to: endOfMonthDay).day ?? 1
        let daysRemainingIncludingToday = max(1, daysRemaining + 1)

        let calculatedBudget = remainingBudget / Double(daysRemainingIncludingToday)
        let roundedBudget = floor(calculatedBudget / roundingStep) * roundingStep

        defaults.set(roundedBudget, forKey: Keys.dailyBudget)
        defaults.set(now, forKey: Keys.dailyBudgetDate)
        defaults.set(currentMonthly, forKey: Keys.lastMonthlyAmountForBudget)

        return roundedBudget
    }

    func saveMonthlyAmount(_ amount: Double) {
        let oldAmount = defaults.double(forKey: Keys.monthlyAmount)
        defaults.set(amount, forKey: Keys.monthlyAmount)
        if oldAmount != amount {
            clearDailyBudgetCache()
        }
        objectWillChange.send()
    }

    func clearDailyBudgetCache() {
        defaults.removeObject(forKey: Keys.dailyBudget)
        defaults.removeObject(forKey: Keys.dailyBudgetDate)
        defaults.removeObject(forKey: Keys.lastMonthlyAmountForBudget)
    }
}
