import Foundation

struct Transaction: Identifiable, Codable {
    let id: UUID
    let amount: String
    let category: String
    let date: Date
    
    init(amount: String, category: String, date: Date = Date()) {
        self.id = UUID()
        self.amount = amount
        self.category = category
        self.date = date
    }
    
    var formattedCategory: String {
        switch category.lowercased() {
        case "продукты", "доставка":
            return "\(category) еда"
        case "кальян":
            return "\(category) алко"
        default:
            return category
        }
    }
}

