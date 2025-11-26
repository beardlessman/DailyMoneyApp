import Foundation
import Combine
import SwiftUI

class TransactionManager: ObservableObject {
    @Published var transactions: [Transaction] = []
    private let storageKey = "transactions"
    
    init() {
        loadTransactions()
    }
    
    func addTransaction(amount: String, category: String) {
        let transaction = Transaction(amount: amount, category: category)
        transactions.append(transaction)
        saveTransactions()
    }
    
    func saveTransactions() {
        if let encoded = try? JSONEncoder().encode(transactions) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    func loadTransactions() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Transaction].self, from: data) {
            transactions = decoded
        }
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
        
        return grouped
    }
    
    func getMonthString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: Date()).capitalized
    }
    
    func getFormattedLog() -> String {
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
            
            if let dayTransactions = grouped[dayStart], !dayTransactions.isEmpty {
                result += "\(dateString)\n"
                for transaction in dayTransactions {
                    result += "\(transaction.amount) \(transaction.formattedCategory)\n"
                }
            } else {
                result += "\(dateString)\n0 бесплатный день\n"
            }
            
            result += "\n"
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

