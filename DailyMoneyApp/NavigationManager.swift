import Foundation
import Combine
import SwiftUI

class NavigationManager: ObservableObject {
    @Published var selectedTab: Int = 0
    
    func switchToLog() {
        withAnimation(nil) {
            selectedTab = 1
        }
    }
    
    func switchToAdd() {
        withAnimation(nil) {
            selectedTab = 0
        }
    }
}

