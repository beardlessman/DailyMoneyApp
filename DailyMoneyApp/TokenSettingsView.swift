import SwiftUI
import UIKit

struct TokenSettingsView: View {
    @ObservedObject var gistStorage = GistStorage.shared
    @EnvironmentObject var transactionManager: TransactionManager
    @Environment(\.dismiss) var dismiss
    @State private var tokenInput: String = ""
    @State private var showToken: Bool = false
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
                        transactionManager.reloadFromFile()
                    }) {
                        Label("Перезагрузить из Gist", systemImage: "arrow.clockwise")
                    }
                    
                    if let gistURL = gistStorage.gistURL {
                        Button(action: {
                            UIApplication.shared.open(gistURL)
                        }) {
                            HStack {
                                Label("Открыть Gist", systemImage: "link")
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                            }
                        }
                    }
                    
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
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GitHub Personal Access Token")
                            .font(.headline)
                        
                        Text("Для работы приложения нужен GitHub Personal Access Token с правами на создание Gist.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if gistStorage.hasToken {
                            HStack {
                                Text("Токен установлен")
                                    .foregroundColor(.green)
                                Spacer()
                                Button("Удалить") {
                                    gistStorage.clearToken()
                                    tokenInput = ""
                                }
                                .foregroundColor(.red)
                            }
                        } else {
                            SecureField("ghp_...", text: $tokenInput)
                                .textContentType(.password)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Авторизация")
                } footer: {
                    Text("Токен хранится в защищенном хранилище устройства и не передается третьим лицам.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Как получить токен:")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Откройте GitHub.com")
                            Text("2. Settings → Developer settings → Personal access tokens → Tokens (classic)")
                            Text("3. Нажмите \"Generate new token\"")
                            Text("4. Выберите scope: \"gist\"")
                            Text("5. Скопируйте токен и вставьте выше")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        Button(action: {
                            if let url = URL(string: "https://github.com/settings/tokens/new") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Text("Открыть GitHub")
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Инструкция")
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
                    .disabled(tokenInput.isEmpty && !gistStorage.hasToken && monthlyAmountInput.isEmpty)
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
            // Не показываем существующий токен из соображений безопасности
            tokenInput = ""
            // Устанавливаем текущее значение бюджета
            monthlyAmountInput = String(Int(defaultMonthlyAmount))
        }
    }
    
    private func saveSettings() {
        // Сохраняем токен, если он введен
        if !tokenInput.isEmpty {
            // Проверяем формат токена (должен начинаться с ghp_)
            if !tokenInput.hasPrefix("ghp_") {
                errorMessage = "Токен должен начинаться с 'ghp_'"
                showError = true
                return
            }
            
            gistStorage.setToken(tokenInput)
            tokenInput = ""
            
            // Перезагружаем данные после установки токена
            Task {
                do {
                    try await gistStorage.initializeIfNeeded()
                } catch {
                    // Ошибка будет показана через TransactionManager
                }
            }
        }
        
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

