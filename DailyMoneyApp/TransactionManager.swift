import Foundation
import Combine
import SwiftUI

class TransactionManager: ObservableObject {
    @Published var transactions: [Transaction] = []
    private let jsonFileName = "transactions.json"
    private let logFileName = "daily_money_log.txt"
    
    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    init() {
        loadTransactions()
    }
    
    func addTransaction(amount: String, category: String) {
        let transaction = Transaction(amount: amount, category: category)
        transactions.append(transaction)
        saveTransactions()
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        transactions.removeAll { $0.id == transaction.id }
        saveTransactions()
    }
    
    func saveTransactions() {
        // Создаем директорию, если её нет
        try? FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        
        // Сохраняем JSON для структурированных данных
        let jsonURL = documentsURL.appendingPathComponent(jsonFileName)
        if let encoded = try? JSONEncoder().encode(transactions) {
            try? encoded.write(to: jsonURL)
        }
        
        // Сохраняем текстовый лог для ручного редактирования
        let logURL = documentsURL.appendingPathComponent(logFileName)
        let logText = getAllTransactionsFormatted()
        try? logText.write(to: logURL, atomically: true, encoding: .utf8)
    }
    
    func loadTransactions() {
        let jsonURL = documentsURL.appendingPathComponent(jsonFileName)
        
        // Пытаемся загрузить из JSON
        if let data = try? Data(contentsOf: jsonURL),
           let decoded = try? JSONDecoder().decode([Transaction].self, from: data) {
            transactions = decoded
            return
        }
        
        // Если JSON нет, пытаемся загрузить из текстового файла
        let logURL = documentsURL.appendingPathComponent(logFileName)
        if let logText = try? String(contentsOf: logURL, encoding: .utf8) {
            parseTransactionsFromLog(logText)
        }
    }
    
    func reloadFromFile() {
        // Перезагружаем транзакции из файла (полезно после ручного редактирования)
        loadTransactions()
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
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
        
        return transactions.filter { transaction in
            transaction.date >= startOfMonth && transaction.date <= endOfMonth
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
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: Date()).capitalized
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
    
    func getLogFileURL() -> URL {
        return documentsURL.appendingPathComponent(logFileName)
    }
    
    func clearAllTransactions() {
        transactions = []
        saveTransactions()
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
}

