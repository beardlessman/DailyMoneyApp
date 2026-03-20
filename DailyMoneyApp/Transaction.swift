import Foundation

struct Transaction: Identifiable, Codable {
    let id: UUID
    let amount: String
    let category: String
    let date: Date
    let timestamp: TimeInterval // Уникальный timestamp для идентификации
    
    // Округляет timestamp до одного знака после точки (всегда .0)
    static func roundTimestamp(_ timestamp: TimeInterval) -> TimeInterval {
        return timestamp.rounded()
    }
    
    // Возвращает округленный timestamp
    var roundedTimestamp: TimeInterval {
        return Transaction.roundTimestamp(timestamp)
    }
    
    init(amount: String, category: String, date: Date = Date()) {
        self.id = UUID()
        self.amount = amount
        self.category = category
        self.date = date
        // Делаем timestamp уникальным: используем точное время + UUID как уникальный идентификатор
        let now = Date()
        let baseTimestamp = now.timeIntervalSince1970
        // Используем UUID для гарантированной уникальности
        // Берем первые 12 символов UUID (без дефисов), конвертируем в число и используем как дробную часть
        let uuidString = self.id.uuidString.replacingOccurrences(of: "-", with: "")
        let uuidPrefix = String(uuidString.prefix(12))
        // Конвертируем hex в число для уникального offset (12 hex символов = максимум 281474976710655)
        let uuidValue = UInt64(uuidPrefix, radix: 16) ?? UInt64.random(in: 0...UInt64.max)
        // Используем больше знаков после запятой для уникальности (до 15 знаков)
        let uniqueOffset = Double(uuidValue % 1000000000000) / 1000000000000.0 // От 0 до 0.999999999999
        // Округляем до одного знака после точки
        self.timestamp = Transaction.roundTimestamp(baseTimestamp + uniqueOffset)
    }
    
    init(amount: String, category: String, date: Date, timestamp: TimeInterval) {
        self.id = UUID()
        self.amount = amount
        self.category = category
        self.date = date
        // Округляем timestamp до одного знака после точки
        self.timestamp = Transaction.roundTimestamp(timestamp)
    }
    
    
}

