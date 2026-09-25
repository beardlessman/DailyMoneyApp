import SwiftUI

@main
struct BudgetApp: App {
    @StateObject private var navigationManager = NavigationManager()
    @StateObject private var transactionManager = TransactionManager()
    @StateObject private var budgetManager = BudgetManager()

    var body: some Scene {
        WindowGroup {
            MainPagerView()
                .environmentObject(navigationManager)
                .environmentObject(transactionManager)
                .environmentObject(budgetManager)
        }
    }
}
