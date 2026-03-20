import SwiftUI
import UIKit

struct LocalLogSettingsView: View {
    @EnvironmentObject var transactionManager: TransactionManager
    @Environment(\.dismiss) var dismiss

    @AppStorage("google_forms_url") private var googleFormsURL: String = ""
    @State private var googleFormsURLInput: String = ""

    @State private var showError = false
    @State private var errorMessage = ""
    
    private struct ShareSheetItem: Identifiable {
        let id = UUID()
        let url: URL
    }
    
    @State private var shareSheetItem: ShareSheetItem?
    @State private var showClearConfirmation = false
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Base URL", text: $googleFormsURLInput)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                    
                    Button("Сохранить") {
                        let trimmed = googleFormsURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // Валидация: чтобы не отправлять запросы с мусором
                        guard !trimmed.isEmpty else {
                            errorMessage = "URL не должен быть пустым."
                            showError = true
                            return
                        }
                        guard URL(string: trimmed) != nil else {
                            errorMessage = "Некорректный URL."
                            showError = true
                            return
                        }
                        
                        googleFormsURL = trimmed
                        dismiss()
                    }
                    .disabled(googleFormsURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Google Form")
                }
                
                Section {
                    Button(action: {
                        if let url = transactionManager.getLogFileURL() {
                            shareSheetItem = ShareSheetItem(url: url)
                        }
                    }) {
                        HStack {
                            Label("Экспортировать лог", systemImage: "square.and.arrow.up")
                            Spacer()
                        }
                    }
                    .disabled(transactionManager.transactions.isEmpty)
                    
                    Button(role: .destructive, action: {
                        showClearConfirmation = true
                    }) {
                        HStack {
                            Label("Очистить лог", systemImage: "trash")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                    .disabled(transactionManager.transactions.isEmpty)
                } header: {
                    Text("Действия")
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
            }
            .onAppear {
                googleFormsURLInput = googleFormsURL
            }
            .alert("Ошибка", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Очистить лог", isPresented: $showClearConfirmation) {
                Button("Отмена", role: .cancel) { }
                Button("Очистить", role: .destructive) {
                    transactionManager.clearAllTransactions()
                    dismiss()
                }
            } message: {
                Text("Вы уверены, что хотите удалить все транзакции? Это действие нельзя отменить.")
            }
            .sheet(item: $shareSheetItem) { item in
                ShareSheet(activityItems: [item.url])
            }
        }
    }
}

#Preview {
    LocalLogSettingsView()
        .environmentObject(TransactionManager())
}

