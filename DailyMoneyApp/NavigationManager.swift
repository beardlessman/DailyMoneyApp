import Foundation
import Combine
import SwiftUI

class NavigationManager: ObservableObject {
    /// 0 — журнал (слева), 1 — форма ввода (справа)
    @Published var selectedTab: Int = 1
    @Published var showBudgetSettings = false
    @Published var showLogSettings = false

    func switchToLog() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showBudgetSettings = false
            showLogSettings = false
            selectedTab = 0
        }
    }

    func switchToAdd() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showBudgetSettings = false
            showLogSettings = false
            selectedTab = 1
        }
    }
}
