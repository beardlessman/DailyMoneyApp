import SwiftUI
import UIKit

struct DayView: View {
    let date: Date
    let grouped: [Date: [Transaction]]
    @ObservedObject var transactionManager: TransactionManager

    private var dayStart: Date {
        Calendar.current.startOfDay(for: date)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yy"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateString)
                .font(.headline)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contextMenu {
                    Button(action: {
                        let logText = transactionManager.getFormattedLogForDate(date)
                        UIPasteboard.general.string = logText
                    }) {
                        Label("Копировать лог за день", systemImage: "doc.on.doc")
                    }
                }

            if let dayTransactions = grouped[dayStart], !dayTransactions.isEmpty {
                ForEach(dayTransactions) { transaction in
                    HStack {
                        Text("\(transaction.amount) \(transaction.category)")
                            .font(.body)
                            .padding(.horizontal, 8)
                        Spacer()
                    }
                    .contextMenu {
                        Button(role: .destructive, action: {
                            transactionManager.deleteTransaction(transaction)
                        }) {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            } else {
                Text("0 бесплатный день")
                    .font(.body)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.bottom, 16)
    }
}
