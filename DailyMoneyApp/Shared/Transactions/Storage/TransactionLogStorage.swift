import Foundation
import Combine
import CryptoKit

final class TransactionLogStorage: ObservableObject {
    static let shared = TransactionLogStorage()
    
    private let cacheFileName = "DailyMoneyLog_cache.csv"
    
    private init() {}

    private func deterministicUUID(from string: String) -> UUID {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        let first16 = digest.prefix(16)
        let hex = first16.map { String(format: "%02x", $0) }.joined()
        // UUID: 8-4-4-4-12
        let part1 = String(hex.prefix(8))
        let part2 = String(hex.dropFirst(8).prefix(4))
        let part3 = String(hex.dropFirst(12).prefix(4))
        let part4 = String(hex.dropFirst(16).prefix(4))
        let part5 = String(hex.dropFirst(20))
        let uuidString = "\(part1)-\(part2)-\(part3)-\(part4)-\(part5)"
        return UUID(uuidString: uuidString) ?? UUID()
    }
    
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
        dayFormatter.dateFormat = "dd.MM.yyyy"
        
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
                        result += "\(transaction.amount) \(transaction.category) [\(dateString)]\n"
                    }
                    
                    result += "\n"
                }
            }
        }
        
        return result.trimmingCharacters(in: .whitespaces) + "\n"
    }
    
    // MARK: - CSV (used for local cache)
    
    /// CSV для локального кэша: содержит `id`, чтобы транзакции были идентичны после перезапуска.
    /// Формат: `id,date,amount,comment` (date в dd.MM.yyyy)
    func formatCacheCSV(_ transactions: [Transaction]) -> String {
        // Убираем дубликаты по UUID
        var uniqueTransactions: [Transaction] = []
        var seenIDs = Set<UUID>()
        
        for transaction in transactions {
            if !seenIDs.contains(transaction.id) {
                uniqueTransactions.append(transaction)
                seenIDs.insert(transaction.id)
            }
        }
        
        // Сортируем по дате (от новых к старым)
        let sorted = uniqueTransactions.sorted { $0.date > $1.date }
        
        var result = "id,date,amount,comment\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ru_RU")
        dateFormatter.dateFormat = "dd.MM.yyyy"
        
        for transaction in sorted {
            let dateStr = dateFormatter.string(from: transaction.date)
            let comment = transaction.category
            let escapedComment = comment.replacingOccurrences(of: "\"", with: "\"\"")
            
            result += "\(transaction.id.uuidString),\(dateStr),\(transaction.amount),\"\(escapedComment)\"\n"
        }
        
        return result
    }
    
    func formatCSV(_ transactions: [Transaction]) -> String {
        // Убираем дубликаты по UUID (чтобы не терять разные события с одинаковыми amount/category)
        var uniqueTransactions: [Transaction] = []
        var seenIDs = Set<UUID>()
        for transaction in transactions {
            if !seenIDs.contains(transaction.id) {
                uniqueTransactions.append(transaction)
                seenIDs.insert(transaction.id)
            }
        }
        
        // Сортируем по дате (от новых к старым)
        let sorted = uniqueTransactions.sorted { $0.date > $1.date }
        
        // Формат CSV: date,amount,comment (date в dd.MM.yyyy)
        var result = "date,amount,comment\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ru_RU")
        dateFormatter.dateFormat = "dd.MM.yyyy"
        
        for transaction in sorted {
            let dateStr = dateFormatter.string(from: transaction.date)
            let comment = transaction.category
            let escapedComment = comment.replacingOccurrences(of: "\"", with: "\"\"")
            
            // Экранируем comment в кавычках
            result += "\(dateStr),\(transaction.amount),\"\(escapedComment)\"\n"
        }
        
        return result
    }
    
    enum CSVParseError: Error {
        case malformedLine
    }
    
    func parseCSV(_ content: String) throws -> [Transaction] {
        let lines = content.components(separatedBy: .newlines)
        var transactions: [Transaction] = []
        
        guard lines.count > 1 else { return [] }
        
        let calendar = Calendar.current
        
        // Парсим заголовок, чтобы определить порядок колонок.
        // Поддерживаем:
        // 1) новый кэш: id,date,amount,comment (id = UUID, date = dd.MM.yyyy)
        // 2) экспорт: date,amount,comment (date = dd.MM.yyyy)
        // 3) старый кэш: timestamp,amount,comment (timestamp = ISO8601)
        let header = lines[0].trimmingCharacters(in: .whitespaces).lowercased()
        let headerColumns = header.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        var amountIndex: Int? = nil
        var commentIndex: Int? = nil
        var idIndex: Int? = nil
        var dateIndex: Int? = nil
        var timestampIndex: Int? = nil
        
        for (i, col) in headerColumns.enumerated() {
            switch col {
            case "amount":
                amountIndex = i
            case "comment":
                commentIndex = i
            case "id":
                idIndex = i
            case "date":
                dateIndex = i
            case "timestamp":
                timestampIndex = i
            default:
                break
            }
        }
        
        guard let amountIdx = amountIndex, let commentIdx = commentIndex else {
            return []
        }
        
        let fullDateFormatter = DateFormatter()
        fullDateFormatter.locale = Locale(identifier: "ru_RU")
        fullDateFormatter.dateFormat = "dd.MM.yyyy"
        
        let shortDateFormatter = DateFormatter()
        shortDateFormatter.locale = Locale(identifier: "ru_RU")
        shortDateFormatter.dateFormat = "dd.MM.yy"
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        var seenIDs = Set<UUID>()
        var seenKeys = Set<String>() // dayStart + amount + category (для форматов без id)
        
        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || lineIndex == 0 { continue }
            
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
            
            let maxNeeded = max(amountIdx, commentIdx, idIndex ?? 0, dateIndex ?? 0, timestampIndex ?? 0)
            guard components.count > maxNeeded else { continue }
            
            let amount = components[amountIdx].trimmingCharacters(in: .whitespaces)
            var comment = components[commentIdx].trimmingCharacters(in: .whitespaces)
            
            if comment.hasPrefix("\"") && comment.hasSuffix("\"") {
                comment = String(comment.dropFirst().dropLast())
            }
            
            let cleanCategory = comment
                .replacingOccurrences(of: " еда", with: "")
                .replacingOccurrences(of: " алко", with: "")
            
            var parsedDate: Date?
            
            if let dIdx = dateIndex {
                let dateStr = components[dIdx].trimmingCharacters(in: .whitespaces)
                parsedDate = fullDateFormatter.date(from: dateStr) ?? shortDateFormatter.date(from: dateStr)
            } else if let tsIdx = timestampIndex {
                let tsStr = components[tsIdx].trimmingCharacters(in: .whitespaces)
                parsedDate = isoFormatter.date(from: tsStr)
            }
            
            guard let date = parsedDate else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let key = "\(dayStart.timeIntervalSince1970)|\(amount)|\(cleanCategory)"
            
            if let idIdx = idIndex {
                let idStr = components[idIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsedID = UUID(uuidString: idStr) {
                    guard !seenIDs.contains(parsedID) else { continue }
                    transactions.append(Transaction(id: parsedID, amount: amount, category: cleanCategory, date: dayStart))
                    seenIDs.insert(parsedID)
                    continue
                }
            }
            
            // Для форматов без id (или если UUID прочитать не получилось)
            guard !seenKeys.contains(key) else { continue }
            let deterministicID = deterministicUUID(from: key)
            transactions.append(Transaction(id: deterministicID, amount: amount, category: cleanCategory, date: dayStart))
            seenKeys.insert(key)
        }
        
        return transactions
    }
}

