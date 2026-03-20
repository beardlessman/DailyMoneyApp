import SwiftUI
import UIKit

struct LocalLogSettingsView: View {
    @EnvironmentObject var transactionManager: TransactionManager
    @Environment(\.dismiss) var dismiss
    
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

