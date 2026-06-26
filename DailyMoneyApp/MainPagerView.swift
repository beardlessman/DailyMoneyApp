import SwiftUI

struct MainPagerView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var transactionManager: TransactionManager

    private let edgeSwipeMargin: CGFloat = 28
    private let swipeDistanceThreshold: CGFloat = 80
    private let pageAnimation: Animation = .easeInOut(duration: 0.3)

    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                HStack(spacing: 0) {
                    LogView()
                        .frame(width: geometry.size.width, height: geometry.size.height)

                    ContentView()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .offset(x: navigationManager.selectedTab == 0 ? 0 : -geometry.size.width)
                .animation(pageAnimation, value: navigationManager.selectedTab)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                .clipped()
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
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
                .sheet(isPresented: $navigationManager.showBudgetSettings) {
                    TokenSettingsView()
                        .environmentObject(transactionManager)
                }
                .sheet(isPresented: $navigationManager.showLogSettings) {
                    LocalLogSettingsView()
                        .environmentObject(transactionManager)
                }
                .simultaneousGesture(screenSwipeGesture(in: geometry.size))
            }
        }
    }

    private func screenSwipeGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > abs(value.translation.height) * 1.5 else { return }

                let startX = value.startLocation.x

                if navigationManager.selectedTab == 1,
                   horizontal > swipeDistanceThreshold,
                   startX < edgeSwipeMargin {
                    navigationManager.switchToLog()
                } else if navigationManager.selectedTab == 0,
                          horizontal < -swipeDistanceThreshold,
                          startX > size.width - edgeSwipeMargin {
                    navigationManager.switchToAdd()
                }
            }
    }
}
