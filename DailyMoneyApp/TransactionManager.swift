import Foundation
import Combine
import SwiftUI

class TransactionManager: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var isLoading: Bool = true
    
    private let gistStorage = GistStorage.shared
    
    init() {
        Task {
            await loadFromCache()
        }
    }
    
    private func loadFromCache() async {
        await MainActor.run {
            isLoading = true
        }
        
        // Загружаем только из локального кэша
        if let cachedContent = gistStorage.loadCache() {
            do {
                var loadedTransactions = try gistStorage.parseCSV(cachedContent)
                // Дополнительная проверка на дубликаты (на всякий случай)
                var uniqueTransactions: [Transaction] = []
                var seenTimestamps = Set<TimeInterval>()
                for transaction in loadedTransactions {
                    // Используем округленный timestamp для сравнения
                    let roundedTimestamp = transaction.roundedTimestamp
                    if !seenTimestamps.contains(roundedTimestamp) {
                        uniqueTransactions.append(transaction)
                        seenTimestamps.insert(roundedTimestamp)
                    }
                }
                loadedTransactions = uniqueTransactions
                await MainActor.run {
                    transactions = loadedTransactions
                    removeDuplicates()
                    isLoading = false
                }
            } catch {
                print("❌ Failed to parse cache: \(error.localizedDescription)")
                await MainActor.run {
                    transactions = []
                    isLoading = false
                }
            }
        } else {
            print("📭 No cache found, starting with empty transactions")
            await MainActor.run {
                transactions = []
                isLoading = false
            }
        }
    }
    
    func addTransaction(amount: String, category: String) {
        let transaction = Transaction(amount: amount, category: category)
        
        let roundedTimestamp = transaction.roundedTimestamp
        if !transactions.contains(where: { $0.roundedTimestamp == roundedTimestamp }) {
            transactions.append(transaction)
            removeDuplicates()
            saveToCache()
        }
    }
    
    private func removeDuplicates() {
        var uniqueTransactions: [Transaction] = []
        var seenTimestamps = Set<TimeInterval>()
        for transaction in transactions {
            let roundedTimestamp = transaction.roundedTimestamp
            if !seenTimestamps.contains(roundedTimestamp) {
                uniqueTransactions.append(transaction)
                seenTimestamps.insert(roundedTimestamp)
            }
        }
        transactions = uniqueTransactions
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        transactions.removeAll { $0.id == transaction.id }
        
        // Сохраняем в локальный кэш
        saveToCache()
    }
    
    private func saveToCache() {
        // Убираем дубликаты перед сохранением
        removeDuplicates()
        // Сохраняем только уникальные транзакции в локальный кэш в CSV формате
        let formatted = gistStorage.formatCSV(transactions)
        gistStorage.saveCache(formatted)
    }
    
    func syncWithGist() {
        Task {
            await MainActor.run {
                isLoading = true
            }
            
            do {
                // Инициализируем Gist, если нужно
                try await gistStorage.initializeIfNeeded()
                
                // Убираем дубликаты из локальных транзакций перед синхронизацией
                removeDuplicates()
                
                // Синхронизируем локальные транзакции с Gist
                // Метод вернет объединенный список без дубликатов
                let syncedTransactions = try await gistStorage.syncWithGist(localTransactions: transactions)
                
                // Сохраняем максимальный timestamp из синхронизированных транзакций
                let maxTimestamp = syncedTransactions.map { $0.timestamp }.max() ?? 0
                UserDefaults.standard.set(maxTimestamp, forKey: "last_sync_timestamp")
                
                // Сохраняем новый список локально
                await MainActor.run {
                    transactions = syncedTransactions
                    removeDuplicates()
                    isLoading = false
                }
                
                // Сохраняем синхронизированные транзакции в кэш
                saveToCache()
            } catch let error as GistStorageError {
                await MainActor.run {
                    errorMessage = error.errorDescription
                    showError = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Неизвестная ошибка: \(error.localizedDescription)"
                    showError = true
                    isLoading = false
                }
            }
        }
    }
    
    func hasUnsynchronizedTransactions() -> Bool {
        let lastSyncTimestamp = UserDefaults.standard.double(forKey: "last_sync_timestamp")
        // Если никогда не синхронизировали, но есть транзакции - показываем кнопку
        if lastSyncTimestamp == 0 {
            return !transactions.isEmpty
        }
        // Проверяем, есть ли транзакции с timestamp больше последнего синхронизированного
        return transactions.contains { $0.timestamp > lastSyncTimestamp }
    }
    
    private func parseTransactionsFromLog(_ logText: String) {
        // Парсим транзакции из текстового лога
        // Это упрощенный парсер - можно улучшить
        let lines = logText.components(separatedBy: .newlines)
        var currentDate: Date?
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ru_RU")
        dateFormatter.dateFormat = "dd.MM.yy"
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // Проверяем, является ли строка датой
            if let date = dateFormatter.date(from: trimmed) {
                currentDate = date
                continue
            }
            
            // Пропускаем заголовки и "бесплатный день"
            if trimmed.contains("бесплатный день") || trimmed.contains("yyyy") || trimmed.contains("LLLL") {
                continue
            }
            
            // Парсим транзакцию: "сумма категория"
            let components = trimmed.components(separatedBy: " ")
            if components.count >= 2, let amount = components.first {
                let category = components.dropFirst().joined(separator: " ")
                // Убираем дополнения "еда" и "алко"
                let cleanCategory = category.replacingOccurrences(of: " еда", with: "").replacingOccurrences(of: " алко", with: "")
                
                if let date = currentDate {
                    let transaction = Transaction(amount: amount, category: cleanCategory, date: date)
                    transactions.append(transaction)
                }
            }
        }
    }
    
    private func getAllTransactionsFormatted() -> String {
        // Форматируем все транзакции по месяцам
        let calendar = Calendar.current
        let groupedByMonth = Dictionary(grouping: transactions) { transaction in
            calendar.date(from: calendar.dateComponents([.year, .month], from: transaction.date))!
        }
        
        var result = ""
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "ru_RU")
        monthFormatter.dateFormat = "LLLL yyyy"
        
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "ru_RU")
        dayFormatter.dateFormat = "dd.MM.yy"
        
        for month in groupedByMonth.keys.sorted(by: >) {
            result += "\(monthFormatter.string(from: month).capitalized)\n\n"
            
            let monthTransactions = groupedByMonth[month]!
            let groupedByDay = Dictionary(grouping: monthTransactions) { transaction in
                calendar.startOfDay(for: transaction.date)
            }
            
            let today = calendar.startOfDay(for: Date())
            
            // Показываем только дни с транзакциями, отсортированные по убыванию
            let daysWithTransactions = groupedByDay.keys
                .filter { dayStart in dayStart <= today }
                .sorted(by: >)
            
            for dayStart in daysWithTransactions {
                if let dayTransactions = groupedByDay[dayStart], !dayTransactions.isEmpty {
                    let dateString = dayFormatter.string(from: dayStart)
                    result += "\(dateString)\n"
                    for transaction in dayTransactions.sorted(by: { $0.date > $1.date }) {
                        result += "\(transaction.amount) \(transaction.formattedCategory)\n"
                    }
                    result += "\n"
                }
            }
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    result += "\(transaction.amount) \(transaction.formattedCategory)\n"
                }
                result += "\n"
            }
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func getLogFileURL() -> URL? {
        // Создаем временный файл в Markdown формате для экспорта
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let exportURL = appSupport.appendingPathComponent("DailyMoneyLog_export.md")
        
        // Форматируем транзакции в Markdown формат
        let markdownContent = gistStorage.formatTransactions(transactions)
        
        // Сохраняем во временный файл
        do {
            try markdownContent.write(to: exportURL, atomically: true, encoding: .utf8)
            return exportURL
        } catch {
            print("❌ Failed to create export file: \(error)")
            return nil
        }
    }
    
    func clearAllTransactions() {
        transactions = []
        
        // Очищаем локальный кэш
        saveToCache()
        
        Task {
            do {
                try await gistStorage.overwriteLog(transactions: [])
            } catch let error as GistStorageError {
                await MainActor.run {
                    errorMessage = error.errorDescription
                    showError = true
                }
            }
        }
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
            result += "\(transaction.amount) \(transaction.formattedCategory)\n"
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

