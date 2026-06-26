import SwiftUI
import UIKit

struct TokenSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var monthlyAmountInput: String = ""
    
    private var defaultMonthlyAmount: Double {
        let savedAmount = UserDefaults.standard.double(forKey: "monthly_amount")
        return savedAmount > 0 ? savedAmount : 120000.0
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Бюджет на месяц")
                            .font(.headline)
                        
                        Text("Укажите ваш месячный бюджет в RSD. Бюджет на день рассчитывается автоматически в 6 утра.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            TextField("120000", text: $monthlyAmountInput)
                                .keyboardType(.numberPad)
                                .textContentType(.none)
                            
                            Text("RSD")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        saveSettings()
                    }
                    .disabled(monthlyAmountInput.isEmpty)
                }
            }
            .alert("Ошибка", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            // Устанавливаем текущее значение бюджета
            monthlyAmountInput = String(Int(defaultMonthlyAmount))
        }
    }
    
    private func saveSettings() {
        // Сохраняем бюджет на месяц
        if !monthlyAmountInput.isEmpty {
            if let amount = Double(monthlyAmountInput), amount > 0 {
                let oldAmount = UserDefaults.standard.double(forKey: "monthly_amount")
                UserDefaults.standard.set(amount, forKey: "monthly_amount")
                
                // Если бюджет изменился, сбрасываем дневной бюджет для пересчета
                if oldAmount != amount {
                    UserDefaults.standard.removeObject(forKey: "daily_budget")
                    UserDefaults.standard.removeObject(forKey: "daily_budget_date")
                    UserDefaults.standard.removeObject(forKey: "last_monthly_amount_for_budget")
                }
            } else {
                errorMessage = "Введите корректную сумму бюджета"
                showError = true
                return
            }
        }
        
        dismiss()
    }
}

#Preview {
    TokenSettingsView()
}

