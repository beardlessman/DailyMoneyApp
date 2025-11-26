import SwiftUI

@main
struct BudgetApp: App {
    @StateObject private var navigationManager = NavigationManager()
    @StateObject private var transactionManager = TransactionManager()
    
    var body: some Scene {
        WindowGroup {
            TabView(selection: $navigationManager.selectedTab) {
                // LogView слева (tag 1)
                LogView()
                    .tag(1)
                    .environmentObject(navigationManager)
                    .environmentObject(transactionManager)
                
                // ContentView справа (tag 0) - начальный экран
                ContentView()
                    .tag(0)
                    .environmentObject(navigationManager)
                    .environmentObject(transactionManager)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}
