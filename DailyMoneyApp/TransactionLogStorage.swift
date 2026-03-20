import Foundation
import Combine

final class TransactionLogStorage: ObservableObject {
    static let shared = TransactionLogStorage()
    
    private let cacheFileName = "DailyMoneyLog_cache.csv"
    
    private init() {}
    
    // MARK: - Cache
    
    func saveCache(_ content: String) {
        guard let cacheURL = getCacheURL() else { return }
        try? content.write(to: cacheURL, atomically: true, encoding: .utf8)
    }
    
    func loadCache() -> String? {
        guard let cacheURL = getCacheURL(),
              FileManager.default.fileExists(atPath: cacheURL.path) else {
            return nil
        }
        return try? String(contentsOf: cacheURL, encoding: .utf8)
    }
    
    private func getCacheURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent(cacheFileName)
    }
    
    // MARK: - Formatting for export / display
    
    func formatTransactions(_ transactions: [Transaction]) -> String {
        let calendar = Calendar.current
        let groupedByMonth = Dictionary(grouping: transactions) { transaction in
            calendar.date(from: calendar.dateComponents([.year, .month], from: transaction.date))!
        }
        
        var result = ""
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "ru_RU")
        monthFormatter.dateFormat = "LLLL"
        
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "ru_RU")
        dayFormatter.dateFormat = "dd.MM.yy"
        
        for month in groupedByMonth.keys.sorted(by: >) {
            let monthTransactions = groupedByMonth[month]!
            let monthSum = monthTransactions.reduce(0.0) { total, t in
                total + (Double(t.amount) ?? 0.0)
            }
            
            result += "\(monthFormatter.string(from: month).capitalized) - \(Int(monthSum))\n\n"
            
            let groupedByDay = Dictionary(grouping: monthTransactions) { transaction in
                calendar.startOfDay(for: transaction.date)
            }
            
            let today = calendar.startOfDay(for: Date())
            let allDays = groupedByDay.keys
                .filter { dayStart in dayStart <= today }
                .sorted(by: >)
            
            for dayStart in allDays {
                let dateString = dayFormatter.string(from: dayStart)
                
                if let dayTransactions = groupedByDay[dayStart] {
                    result += "\(dateString)\n"
                    
                    // "бесплатный день" всегда первым, остальное по убыванию даты
                    let sortedTransactions = dayTransactions.sorted { t1, t2 in
                        if t1.category == "бесплатный день" { return true }
                        if t2.category == "бесплатный день" { return false }
                        return t1.date > t2.date
                    }
                    
                    for transaction in sortedTransactions {
                        if transaction.category == "бесплатный день" {
                            result += "0 бесплатный день [\(Int(transaction.timestamp))]\n"
                        } else {
                            result += "\(transaction.amount) \(transaction.formattedCategory) [\(Int(transaction.timestamp))]\n"
                        }
                    }
                    
                    result += "\n"
                }
            }
        }
        
        return result.trimmingCharacters(in: .whitespaces) + "\n"
    }
    
    // MARK: - CSV (used for local cache)
    
    func formatCSV(_ transactions: [Transaction]) -> String {
        // Убираем дубликаты перед форматированием
        var uniqueTransactions: [Transaction] = []
        var seenTimestamps = Set<TimeInterval>()
        for transaction in transactions {
            let roundedTimestamp = transaction.roundedTimestamp
            if !seenTimestamps.contains(roundedTimestamp) {
                uniqueTransactions.append(transaction)
                seenTimestamps.insert(roundedTimestamp)
            }
        }
        
        // Сортируем по timestamp (от новых к старым)
        let sorted = uniqueTransactions.sorted { $0.timestamp > $1.timestamp }
        
        // Новый формат: timestamp,amount,comment
        var result = "timestamp,amount,comment\n"
        
        // Используем формат без дробных секунд: 2025-11-27T19:13:24Z
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC
        
        for transaction in sorted {
            let timestampDate = Date(timeIntervalSince1970: transaction.timestamp)
            let timestampISO = dateFormatter.string(from: timestampDate)
            
            let comment = transaction.category == "бесплатный день"
                ? "бесплатный день"
                : transaction.formattedCategory
            
            // Экранируем comment в кавычках (timestamp без кавычек)
            result += "\(timestampISO),\(transaction.amount),\"\(comment)\"\n"
        }
        
        return result
    }
    
    enum CSVParseError: Error {
        case malformedLine
    }
    
    func parseCSV(_ content: String) throws -> [Transaction] {
        let lines = content.components(separatedBy: .newlines)
        var transactions: [Transaction] = []
        var seenTimestamps = Set<TimeInterval>() // Для отслеживания дубликатов
        
        guard lines.count > 1 else { return [] }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC
        
        // Определяем порядок столбцов по заголовку, чтобы поддерживать старый формат:
        // timestamp,amount,comment
        // и новый:
        // amount,comment,timestamp
        let header = lines[0].trimmingCharacters(in: .whitespaces).lowercased()
        let headerColumns = header.components(separatedBy: ",")
        
        var amountIndex = 0
        var commentIndex = 1
        var timestampIndex = 2
        
        if headerColumns.count >= 3 {
            for (i, col) in headerColumns.enumerated() {
                let name = col.trimmingCharacters(in: .whitespaces)
                if name == "amount" { amountIndex = i }
                else if name == "comment" { commentIndex = i }
                else if name == "timestamp" { timestampIndex = i }
            }
        } else if header.hasPrefix("timestamp") {
            // Явно поддерживаем старый формат без корректного заголовка
            timestampIndex = 0
            amountIndex = 1
            commentIndex = 2
        }
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || index == 0 { continue }
            
            // CSV парсер с поддержкой кавычек в comment
            var components: [String] = []
            var currentComponent = ""
            var inQuotes = false
            
            for char in trimmed {
                if char == "\"" {
                    inQuotes.toggle()
                } else if char == "," && !inQuotes {
                    components.append(currentComponent)
                    currentComponent = ""
                } else {
                    currentComponent.append(char)
                }
            }
            components.append(currentComponent)
            
            if components.count <= max(timestampIndex, max(amountIndex, commentIndex)) {
                continue
            }
            
            let amount = components[amountIndex].trimmingCharacters(in: .whitespaces)
            var comment = components[commentIndex].trimmingCharacters(in: .whitespaces)
            let timestampStr = components[timestampIndex].trimmingCharacters(in: .whitespaces)
            
            // Убираем кавычки из комментария, если они вдруг остались
            if comment.hasPrefix("\"") && comment.hasSuffix("\"") {
                comment = String(comment.dropFirst().dropLast())
            }
            
            let cleanCategory = comment
                .replacingOccurrences(of: " еда", with: "")
                .replacingOccurrences(of: " алко", with: "")
            
            // Парсим timestamp - поддерживаем оба формата (с дробными секундами и без)
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            fractionalFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            
            let timestampDate = fractionalFormatter.date(from: timestampStr) ?? dateFormatter.date(from: timestampStr)
            guard let date = timestampDate else { continue }
            
            let timestamp = date.timeIntervalSince1970
            let roundedTimestamp = Transaction.roundTimestamp(timestamp)
            
            if !seenTimestamps.contains(roundedTimestamp) {
                let transaction = Transaction(amount: amount, category: cleanCategory, date: date, timestamp: roundedTimestamp)
                transactions.append(transaction)
                seenTimestamps.insert(roundedTimestamp)
            }
        }
        
        return transactions
    }
}

