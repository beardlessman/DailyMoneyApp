import SwiftUI

struct GistSettingsView: View {
    @ObservedObject var gistStorage = GistStorage.shared
    @EnvironmentObject var transactionManager: TransactionManager
    @Environment(\.dismiss) var dismiss
    @State private var tokenInput: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                if gistStorage.hasToken {
                    Section {
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
                    } header: {
                        Text("Действия")
                    }
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
                                    dismiss()
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
            .navigationTitle("Настройки Gist")
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
                    .disabled(tokenInput.isEmpty && !gistStorage.hasToken)
                }
            }
            .alert("Ошибка", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            // Не показываем существующий токен из соображений безопасности
            tokenInput = ""
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
        }
        
        dismiss()
    }
}

#Preview {
    GistSettingsView()
        .environmentObject(TransactionManager())
}

