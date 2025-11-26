import SwiftUI

struct LogView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var transactionManager: TransactionManager
    @State private var showCopyAlert = false
    
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
        let allDays = getDaysInMonth(start: monthRange.start, end: monthRange.end)
        return allDays.filter { Calendar.current.startOfDay(for: $0) <= today }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Заголовок месяца с кнопкой копирования
                    HStack {
                        Button(action: {
                            copyLogToClipboard()
                            showCopyAlert = true
                        }) {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.blue)
                                .font(.title3)
                        }
                        
                        Text(transactionManager.getMonthString())
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                    
                    // Список дней
                    ForEach(daysInMonth.reversed(), id: \.self) { date in
                        DayView(date: date, grouped: groupedTransactions)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 20)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        navigationManager.switchToAdd()
                    }) {
                        Image(systemName: "arrow.right")
                            .foregroundColor(.blue)
                    }
                }
            }
            .alert("Лог скопирован", isPresented: $showCopyAlert) {
                Button("OK", role: .cancel) { }
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
    
    private func copyLogToClipboard() {
        let logText = transactionManager.getFormattedLog()
        UIPasteboard.general.string = logText
    }
}

struct DayView: View {
    let date: Date
    let grouped: [Date: [Transaction]]
    
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
                .padding(.top, 16)
            
            if let dayTransactions = grouped[dayStart], !dayTransactions.isEmpty {
                ForEach(dayTransactions) { transaction in
                    Text("\(transaction.amount) \(transaction.formattedCategory)")
                        .font(.body)
                        .padding(.horizontal, 8)
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
