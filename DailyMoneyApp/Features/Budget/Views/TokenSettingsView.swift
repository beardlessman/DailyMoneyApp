import SwiftUI
import UIKit

struct TokenSettingsView: View {
    @EnvironmentObject var budgetManager: BudgetManager
    @Environment(\.dismiss) var dismiss
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var monthlyAmountInput: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Бюджет на месяц")
                            .font(.headline)

                        Text("Укажите ваш месячный бюджет в RSD. Бюджет на день рассчитывается автоматически раз в календарный день.")
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
            monthlyAmountInput = String(Int(budgetManager.monthlyAmount))
        }
    }

    private func saveSettings() {
        guard !monthlyAmountInput.isEmpty else {
            dismiss()
            return
        }

        guard let amount = Double(monthlyAmountInput), amount > 0 else {
            errorMessage = "Введите корректную сумму бюджета"
            showError = true
            return
        }

        budgetManager.saveMonthlyAmount(amount)
        dismiss()
    }
}

#Preview {
    TokenSettingsView()
        .environmentObject(BudgetManager())
}
