import SwiftUI
import UIKit

struct LogView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var transactionManager: TransactionManager
    @AppStorage("monthly_amount") private var monthlyAmount: Double = 120000.0

    private var effectiveMonthlyAmount: Double {
        monthlyAmount > 0 ? monthlyAmount : 120000.0
    }

    private var monthSpentAmount: Double {
        transactionManager.getMonthSpentAmount()
    }

    private var remainingUntilEndOfMonth: Double {
        effectiveMonthlyAmount - monthSpentAmount
    }

    private var groupedTransactions: [Date: [Transaction]] {
        transactionManager.getGroupedTransactions()
    }

    private var daysInMonth: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return groupedTransactions.keys.filter { dayStart in
            dayStart <= today && !groupedTransactions[dayStart]!.isEmpty
        }.sorted(by: >)
    }

    private var hasTransactions: Bool {
        !daysInMonth.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if hasTransactions {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transactionManager.getMonthString())
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("\(Int(monthSpentAmount)) RSD потрачено")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("\(Int(remainingUntilEndOfMonth)) RSD до конца месяца")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .contextMenu {
                        Button(action: {
                            let logText = transactionManager.getFormattedLog()
                            UIPasteboard.general.string = logText
                        }) {
                            Label("Копировать лог за месяц", systemImage: "doc.on.doc")
                        }
                    }
                    .padding(.bottom, 8)

                    ForEach(daysInMonth, id: \.self) { date in
                        DayView(date: date, grouped: groupedTransactions, transactionManager: transactionManager)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 24)
            .padding(.bottom, 100)
        }
    }
}

// Share Sheet для экспорта файла
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

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

#Preview {
    LogView()
        .environmentObject(NavigationManager())
        .environmentObject(TransactionManager())
}
