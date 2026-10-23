import Foundation

struct Transaction: Identifiable, Codable {
    let id: UUID
    let amount: String
    let category: String
    let date: Date
    
    init(id: UUID, amount: String, category: String, date: Date) {
        self.id = id
        self.amount = amount
        self.category = category
        self.date = date
    }
    
    init(amount: String, category: String, date: Date = Date()) {
        self.init(id: UUID(), amount: amount, category: category, date: date)
    }
}

