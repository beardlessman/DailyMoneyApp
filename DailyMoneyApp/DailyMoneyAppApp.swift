import SwiftUI

@main
struct BudgetApp: App {
    @StateObject private var navigationManager = NavigationManager()
    
    var body: some Scene {
        WindowGroup {
            TabView(selection: $navigationManager.selectedTab) {
                // LogView слева (tag 1)
                LogView()
                    .tag(1)
                    .environmentObject(navigationManager)
                
                // ContentView справа (tag 0) - начальный экран
                ContentView()
                    .tag(0)
                    .environmentObject(navigationManager)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}
