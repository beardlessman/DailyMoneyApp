import Foundation

enum ExpenseCategories {
    static let suggestions = [
        "Продукты", "Доставка", "Алкоголь", "Кальян", "Машина", "Платежи",
        "Для дома", "Здоровье", "Кофе", "Подписки", "Подарки", "Отдых",
        "Авиабилеты", "Другое"
    ]

    static func extract(from comment: String) -> String {
        let commentLower = comment.lowercased()
        let ordered = suggestions.sorted { $0.count > $1.count }
        for suggestion in ordered where commentLower.contains(suggestion.lowercased()) {
            return suggestion
        }
        return comment
    }
}
