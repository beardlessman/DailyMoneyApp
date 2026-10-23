import SwiftUI
import UIKit

struct LogView: View {
    @EnvironmentObject var transactionManager: TransactionManager
    @EnvironmentObject var budgetManager: BudgetManager

    private var monthSpentAmount: Double {
        transactionManager.getMonthSpentAmount()
    }

    private var remainingUntilEndOfMonth: Double {
        budgetManager.remainingUntilEndOfMonth(monthSpent: monthSpentAmount)
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
            .padding(.bottom, 100)
        }
    }
}

#Preview {
    LogView()
        .environmentObject(TransactionManager())
        .environmentObject(BudgetManager())
}
