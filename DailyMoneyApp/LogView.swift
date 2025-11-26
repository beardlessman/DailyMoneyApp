import SwiftUI

struct LogView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Лог транзакций")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
                
                Text("Здесь будет список всех транзакций")
                    .foregroundColor(.secondary)
                    .padding()
                
                Spacer()
            }
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
        }
    }
}

#Preview {
    LogView()
        .environmentObject(NavigationManager())
}

