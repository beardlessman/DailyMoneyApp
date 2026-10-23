import Foundation
import Combine
import SwiftUI

class NavigationManager: ObservableObject {
    static let logTab = "log"
    static let formTab = "form"

    @Published var selectedTab: String = formTab
    @Published var showBudgetSettings = false
    @Published var showLogSettings = false

    func switchToLog() {
        showBudgetSettings = false
        showLogSettings = false
        selectedTab = Self.logTab
    }

    func switchToAdd() {
        showBudgetSettings = false
        showLogSettings = false
        selectedTab = Self.formTab
    }
}
