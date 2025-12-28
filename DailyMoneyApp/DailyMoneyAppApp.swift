import SwiftUI
import UIKit

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
            .background(TabBarHider())
        }
    }
}

// Помощник для скрытия tab bar
struct TabBarHider: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Находим TabBarController и скрываем tab bar
            if let window = uiView.window {
                findAndHideTabBar(in: window)
            }
        }
    }
    
    private func findAndHideTabBar(in view: UIView) {
        if let tabBarController = findTabBarController(in: view) {
            tabBarController.tabBar.isHidden = true
        }
        
        // Также ищем UITabBar напрямую
        for subview in view.subviews {
            if let tabBar = subview as? UITabBar {
                tabBar.isHidden = true
            }
            findAndHideTabBar(in: subview)
        }
    }
    
    private func findTabBarController(in view: UIView) -> UITabBarController? {
        var responder: UIResponder? = view
        var depth = 0
        while responder != nil && depth < 20 {
            if let tabBarController = responder as? UITabBarController {
                return tabBarController
            }
            responder = responder?.next
            depth += 1
        }
        return nil
    }
}
