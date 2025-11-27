import SwiftUI

struct Toast: Identifiable {
    let id = UUID()
    let message: String
}

struct ContentView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var transactionManager: TransactionManager
    @State private var amount: String = ""
    @State private var comment: String = "Продукты"
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isCommentFocused: Bool
    @State private var toasts: [Toast] = []
    
    let categorySuggestions = ["Продукты", "Доставка", "Алкоголь", "Кальян", "Транспорт", "Платежи", "Для дома", "Здоровье", "Кофе"]
    
    private var MONTHLY_AMOUNT: Double {
        let savedAmount = UserDefaults.standard.double(forKey: "monthly_amount")
        return savedAmount > 0 ? savedAmount : 120000.0 // Значение по умолчанию
    }
    
    private var dailyBudget: Double {
        let calendar = Calendar.current
        let now = Date()
        
        // Проверяем, нужно ли пересчитать дневной бюджет
        let lastCalculationDate = UserDefaults.standard.object(forKey: "daily_budget_date") as? Date
        let today6AM = getToday6AM()
        let today = calendar.startOfDay(for: now)
        
        // Пересчитываем, если:
        // 1. Бюджет никогда не рассчитывался
        // 2. Бюджет рассчитывался не сегодня
        // 3. Бюджет рассчитывался сегодня, но до 6 утра, а сейчас уже после 6 утра
        let shouldRecalculate: Bool
        if let lastDate = lastCalculationDate {
            let lastDateDay = calendar.startOfDay(for: lastDate)
            if lastDateDay < today {
                // Бюджет рассчитывался вчера или раньше
                shouldRecalculate = true
            } else if lastDateDay == today && lastDate < today6AM && now >= today6AM {
                // Бюджет рассчитывался сегодня до 6 утра, а сейчас уже после 6 утра
                shouldRecalculate = true
            } else {
                // Бюджет уже рассчитан сегодня после 6 утра
                shouldRecalculate = false
            }
        } else {
            // Бюджет никогда не рассчитывался
            shouldRecalculate = true
        }
        
        if shouldRecalculate {
            // Рассчитываем новый дневной бюджет
            let monthSpent = transactionManager.getMonthSpentAmount()
            let remainingBudget = MONTHLY_AMOUNT - monthSpent
            
            // Рассчитываем остаток дней в месяце (включая сегодня)
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
            let today = calendar.startOfDay(for: now)
            let endOfMonthDay = calendar.startOfDay(for: endOfMonth)
            
            // Количество дней от сегодня до конца месяца включительно
            let daysRemaining = calendar.dateComponents([.day], from: today, to: endOfMonthDay).day ?? 1
            let daysRemainingIncludingToday = max(1, daysRemaining + 1)
            
            // Бюджет на день = остаток бюджета / остаток дней
            let calculatedBudget = remainingBudget / Double(daysRemainingIncludingToday)
            
            // Округляем до меньшего значения с точностью до 500 RSD
            let roundedBudget = floor(calculatedBudget / 500.0) * 500.0
            
            // Сохраняем рассчитанный бюджет и дату расчета
            UserDefaults.standard.set(roundedBudget, forKey: "daily_budget")
            UserDefaults.standard.set(now, forKey: "daily_budget_date")
            
            return roundedBudget
        } else {
            // Используем сохраненный бюджет
            let savedBudget = UserDefaults.standard.double(forKey: "daily_budget")
            return savedBudget > 0 ? savedBudget : 0
        }
    }
    
    private var availableAmount: Double {
        // Доступная сумма = дневной бюджет - траты сегодня
        let todaySpent = transactionManager.getTodaySpentAmount()
        return dailyBudget - todaySpent
    }
    
    private func getToday6AM() -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 6
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? now
    }
    
    private var amountColor: Color {
        let available = availableAmount
        let halfDailyBudget = dailyBudget / 2.0
        
        if available > halfDailyBudget {
            return .green
        } else if available < 0 {
            return .red
        } else {
            return .black
        }
    }
    
    private func submitForm() {
        // Если категория не выбрана, подставляем "что-то"
        let categoryText = comment.isEmpty ? "что-то" : comment
        
        // Сохраняем транзакцию
        transactionManager.addTransaction(amount: amount, category: categoryText)
        
        // Формируем сообщение и добавляем тост
        let toast = Toast(message: "\(amount) \(categoryText)")
        withAnimation {
            toasts.append(toast)
        }
        
        // Очистка формы после сабмита
        amount = ""
        comment = "Продукты"
        isAmountFocused = true
        
        // Автоматически удаляем тост через 3 секунды
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                toasts.removeAll { $0.id == toast.id }
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 24) {
                    // Отображение доступной суммы
                    // Показываем только после загрузки транзакций
                    if transactionManager.isLoading && transactionManager.transactions.isEmpty {
                        // Показываем placeholder только при первой загрузке (когда транзакций еще нет)
                        Text("...")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 8)
                    } else {
                        Text("\(Int(availableAmount)) RSD")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(amountColor)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 8)
                    }
                    
                ZStack(alignment: .trailing) {
                    TextField("Сумма", text: $amount)
                        .keyboardType(.numberPad)
                        .font(.system(size: 28))
                        .multilineTextAlignment(.center)
                        .padding()
                        .focused($isAmountFocused)
                        .submitLabel(.next)
                        .onSubmit {
                            isAmountFocused = false
                            isCommentFocused = true
                        }
                    
                    if !amount.isEmpty {
                        Button(action: {
                            amount = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal, 32)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(categorySuggestions, id: \.self) { suggestion in
                            Button(action: {
                                comment = suggestion
                            }) {
                                Text(suggestion)
                                    .font(.system(size: 16))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(comment == suggestion ? Color.blue : Color(.systemGray5))
                                    .foregroundColor(comment == suggestion ? .white : .primary)
                                    .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                }

                ZStack(alignment: .trailing) {
                    TextField("Категория", text: $comment)
                        .font(.system(size: 20))
                        .padding()
                        .focused($isCommentFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isCommentFocused = false
                        }
                    
                    if !comment.isEmpty {
                        Button(action: {
                            comment = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal, 32)

                Button(action: submitForm) {
                    Text("Добавить")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .disabled(amount.isEmpty)

                Spacer()
            }
            .padding(.top, 100)
            .onAppear {
                if navigationManager.selectedTab == 0 {
                    isAmountFocused = true
                }
            }
            .onChange(of: navigationManager.selectedTab) { newValue in
                if newValue == 0 {
                    // Возврат на экран формы - ставим фокус
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isAmountFocused = true
                    }
                } else {
                    // Переход в лог - убираем фокус
                    isAmountFocused = false
                    isCommentFocused = false
                }
            }
            
            // Всплывающие сообщения сверху в стопке
            if !toasts.isEmpty {
                VStack(spacing: 8) {
                    ForEach(toasts) { toast in
                        Text(toast.message)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                }
                .padding(.top, 50)
            }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        // Убираем фокус перед переходом
                        isAmountFocused = false
                        isCommentFocused = false
                        navigationManager.switchToLog()
                    }) {
                        Image(systemName: "list.bullet")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
