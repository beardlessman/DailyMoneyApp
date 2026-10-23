import Foundation
import Combine

class TransactionManager: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var isLoading: Bool = true

    private let logStorage = TransactionLogStorage.shared

    init() {
        Task {
            await loadFromCache()
        }
    }

    private func loadFromCache() async {
        await MainActor.run {
            isLoading = true
        }

        if let cachedContent = logStorage.loadCache() {
            do {
                let parsedTransactions = try logStorage.parseCSV(cachedContent)
                await MainActor.run {
                    transactions = parsedTransactions
                    removeDuplicates()
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    transactions = []
                    isLoading = false
                }
            }
        } else {
            await MainActor.run {
                transactions = []
                isLoading = false
            }
        }
    }

    func addTransaction(amount: String, category: String) {
        transactions.append(Transaction(amount: amount, category: category))
        saveToCache()
    }

    private func removeDuplicates() {
        var uniqueTransactions: [Transaction] = []
        var seenIDs = Set<UUID>()
        for transaction in transactions {
            if !seenIDs.contains(transaction.id) {
                uniqueTransactions.append(transaction)
                seenIDs.insert(transaction.id)
            }
        }
        transactions = uniqueTransactions
    }

    func deleteTransaction(_ transaction: Transaction) {
        transactions.removeAll { $0.id == transaction.id }
        saveToCache()
    }

    private func saveToCache() {
        removeDuplicates()
        logStorage.saveCache(logStorage.formatCacheCSV(transactions))
    }

    func getTransactionsForCurrentMonth() -> [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        // Вычисляем начало следующего месяца для правильного сравнения
        let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
        
        return transactions.filter { transaction in
            // Используем startOfDay для правильного сравнения дат в локальном часовом поясе
            let transactionDayStart = calendar.startOfDay(for: transaction.date)
            let monthStart = calendar.startOfDay(for: startOfMonth)
            // Транзакция попадает в текущий месяц, если её день >= начала месяца и < начала следующего месяца
            return transactionDayStart >= monthStart && transactionDayStart < nextMonthStart
        }
    }
    
    func getGroupedTransactions() -> [Date: [Transaction]] {
        let monthTransactions = getTransactionsForCurrentMonth()
        let calendar = Calendar.current
        
        var grouped: [Date: [Transaction]] = [:]
        
        for transaction in monthTransactions {
            let dayStart = calendar.startOfDay(for: transaction.date)
            if grouped[dayStart] == nil {
                grouped[dayStart] = []
            }
            grouped[dayStart]?.append(transaction)
        }
        
        // Сортируем транзакции внутри каждого дня по дате (новые сверху)
        for (day, transactions) in grouped {
            grouped[day] = transactions.sorted { $0.date > $1.date }
        }
        
        return grouped
    }
    
    func getMonthString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL"
        return formatter.string(from: Date()).capitalized
    }
    
    func getMonthSpentAmount() -> Double {
        let monthTransactions = getTransactionsForCurrentMonth()
        return monthTransactions.reduce(0.0) { total, transaction in
            total + (Double(transaction.amount) ?? 0.0)
        }
    }
    
    func getFormattedLog() -> String {
        // Используем текущий месяц для копирования
        let grouped = getGroupedTransactions()
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yy"
        
        var result = "\(getMonthString())\n\n"
        
        // Получаем все дни месяца
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
        
        let today = calendar.startOfDay(for: Date())
        var currentDate = endOfMonth
        
        while currentDate >= startOfMonth {
            let dayStart = calendar.startOfDay(for: currentDate)
            
            // Пропускаем будущие даты
            if dayStart > today {
                currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
                continue
            }
            
            let dateString = formatter.string(from: currentDate)
            
            // Показываем только дни с транзакциями
            if let dayTransactions = grouped[dayStart], !dayTransactions.isEmpty {
                result += "\(dateString)\n"
                for transaction in dayTransactions {
                    result += "\(transaction.amount) \(transaction.category)\n"
                }
                result += "\n"
            }
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func getLogFileURL() -> URL? {
        let exportDir = FileManager.default.temporaryDirectory

        let now = Date()
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "ru_RU")
        monthFormatter.dateFormat = "LLLL"
        let monthName = monthFormatter.string(from: now)
        let year = Calendar.current.component(.year, from: now)

        let safeMonthName = monthName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")

        let exportURL = exportDir.appendingPathComponent("DailyMoneyLog_\(safeMonthName)_\(year).csv")
        let csvContent = logStorage.formatCSV(getTransactionsForCurrentMonth())

        do {
            try csvContent.write(to: exportURL, atomically: true, encoding: .utf8)
            return exportURL
        } catch {
            return nil
        }
    }

    func clearAllTransactions() {
        transactions = []
        saveToCache()
    }
    
    func getTodaySpentAmount() -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let todayTransactions = transactions.filter { transaction in
            calendar.startOfDay(for: transaction.date) == today
        }
        
        return todayTransactions.reduce(0.0) { total, transaction in
            total + (Double(transaction.amount) ?? 0.0)
        }
    }
    
    func getFormattedLogForDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        let dayTransactions = transactions.filter { transaction in
            calendar.startOfDay(for: transaction.date) == dayStart
        }.sorted { $0.date > $1.date }
        
        guard !dayTransactions.isEmpty else {
            return ""
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yy"
        let dateString = formatter.string(from: date)
        
        var result = "\(dateString)\n"
        for transaction in dayTransactions {
            result += "\(transaction.amount) \(transaction.category)\n"
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

