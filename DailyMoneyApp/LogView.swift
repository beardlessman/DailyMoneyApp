import SwiftUI
import UIKit

struct LogView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var transactionManager: TransactionManager
    @State private var showGistSettings = false
    @State private var hasSwitchedToAdd = false
    
    private var groupedTransactions: [Date: [Transaction]] {
        transactionManager.getGroupedTransactions()
    }
    
    private var monthRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
        return (startOfMonth, endOfMonth)
    }
    
    private var daysInMonth: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        // Показываем только дни с транзакциями
        return groupedTransactions.keys.filter { dayStart in
            dayStart <= today && !groupedTransactions[dayStart]!.isEmpty
        }.sorted(by: >)
    }
    
    private var hasTransactions: Bool {
        !daysInMonth.isEmpty
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Заголовок месяца (только если есть транзакции)
                        if hasTransactions {
                            HStack {
                                Text(transactionManager.getMonthString())
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 10)
                                Spacer()
                                Text("\(Int(transactionManager.getMonthSpentAmount())) RSD")
                                    .font(.title3)
                            }
                            .contextMenu {
                                Button(action: {
                                    let logText = transactionManager.getFormattedLog()
                                    UIPasteboard.general.string = logText
                                }) {
                                    Label("Копировать лог за месяц", systemImage: "doc.on.doc")
                                }
                            }
                            
                            
                            // Список дней (уже отсортированы в обратном порядке)
                            ForEach(daysInMonth, id: \.self) { date in
                                DayView(date: date, grouped: groupedTransactions, transactionManager: transactionManager)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 100) // Отступ снизу для кнопки синхронизации
                }
                
                // Кнопка синхронизации справа внизу (только если есть несинхронизированные транзакции)
                if transactionManager.hasUnsynchronizedTransactions() {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                transactionManager.syncWithGist()
                            }) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.blue)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(radius: 5)
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showGistSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(.blue)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Image(systemName: "arrow.right")
                        .foregroundColor(.blue)
                        .background(Color.clear)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !hasSwitchedToAdd {
                                        hasSwitchedToAdd = true
                                        navigationManager.switchToAdd()
                                    }
                                }
                                .onEnded { _ in
                                    hasSwitchedToAdd = false
                                }
                        )
                        .transaction { $0.animation = nil }
                }
            }
            .sheet(isPresented: $showGistSettings) {
                GistSettingsView()
                    .environmentObject(transactionManager)
            }
        }
    }
    
    private func getDaysInMonth(start: Date, end: Date) -> [Date] {
        var days: [Date] = []
        var currentDate = start
        let calendar = Calendar.current
        
        while currentDate <= end {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
}

// Share Sheet для экспорта файла
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Ничего не делаем
    }
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
                        Text("\(transaction.amount) \(transaction.formattedCategory)")
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
    }
}

#Preview {
    LogView()
        .environmentObject(NavigationManager())
        .environmentObject(TransactionManager())
}
