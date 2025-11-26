import Foundation
import Combine
import SwiftUI

class NavigationManager: ObservableObject {
    @Published var selectedTab: Int = 0
    
    func switchToLog() {
        selectedTab = 1
    }
    
    func switchToAdd() {
        selectedTab = 0
    }
}

