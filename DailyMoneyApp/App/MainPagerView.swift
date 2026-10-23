import SwiftUI

struct MainPagerView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var transactionManager: TransactionManager
    @EnvironmentObject var budgetManager: BudgetManager

    var body: some View {
        NavigationStack {
            TabView(selection: $navigationManager.selectedTab) {
                LogView()
                    .tag(NavigationManager.logTab)

                ContentView()
                    .tag(NavigationManager.formTab)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: navigationManager.selectedTab)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { mainToolbar }
            .sheet(isPresented: $navigationManager.showBudgetSettings) {
                TokenSettingsView()
                    .environmentObject(budgetManager)
            }
            .sheet(isPresented: $navigationManager.showLogSettings) {
                LocalLogSettingsView()
                    .environmentObject(transactionManager)
            }
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if navigationManager.selectedTab == NavigationManager.formTab {
                Button(action: navigationManager.switchToLog) {
                    Image(systemName: "list.bullet")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    navigationManager.showLogSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }

        if navigationManager.selectedTab == NavigationManager.logTab {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: navigationManager.switchToAdd) {
                    Image(systemName: "arrow.right")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
