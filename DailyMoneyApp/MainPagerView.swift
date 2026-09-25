import SwiftUI

struct MainPagerView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var transactionManager: TransactionManager

    var body: some View {
        NavigationStack {
            TabView(selection: $navigationManager.selectedTab) {
                LogView()
                    .tag(0)

                ContentView()
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: navigationManager.selectedTab)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { mainToolbar }
            .sheet(isPresented: $navigationManager.showBudgetSettings) {
                TokenSettingsView()
                    .environmentObject(transactionManager)
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
            if navigationManager.selectedTab == 1 {
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

        if navigationManager.selectedTab == 0 {
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
