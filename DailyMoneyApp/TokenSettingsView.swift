import SwiftUI
import UIKit

struct TokenSettingsView: View {
    @EnvironmentObject var transactionManager: TransactionManager
    @Environment(\.dismiss) var dismiss
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var monthlyAmountInput: String = ""
    @State private var showShareSheet = false
    @State private var showClearConfirmation = false
    
    private var defaultMonthlyAmount: Double {
        let savedAmount = UserDefaults.standard.double(forKey: "monthly_amount")
        return savedAmount > 0 ? savedAmount : 120000.0
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Button(action: {
                        if let url = transactionManager.getLogFileURL() {
                            showShareSheet = true
                        }
                    }) {
                        Label("Экспортировать лог", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(role: .destructive, action: {
                        showClearConfirmation = true
                    }) {
                        Label("Очистить лог", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Действия")
                }
                
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
                } header: {
                    Text("Бюджет")
                } footer: {
                    Text("Текущее значение: \(Int(defaultMonthlyAmount)) RSD")
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
            .alert("Очистить весь лог?", isPresented: $showClearConfirmation) {
                Button("Отмена", role: .cancel) { }
                Button("Очистить", role: .destructive) {
                    transactionManager.clearAllTransactions()
                }
            } message: {
                Text("Все транзакции будут удалены. Это действие нельзя отменить.")
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = transactionManager.getLogFileURL() {
                    ShareSheet(activityItems: [url])
                }
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
                UserDefaults.standard.set(amount, forKey: "monthly_amount")
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
        .environmentObject(TransactionManager())
}

