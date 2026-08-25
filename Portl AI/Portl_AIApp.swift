//
//  Portl_AIApp.swift
//  Portl AI
//
//  Created by ardy on 2026-03-06.
//

import SwiftUI
import UIKit

// Lock the entire app to portrait orientation
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}

@main
struct Portl_AIApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var auth = AuthManager.shared
    @State private var theme = ThemeManager.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        FontRegistration.registerFonts()
        configureAppearance()
        AuthManager.shared.configure()
    }

    private func configureAppearance() {
        // Navigation bar titles
        let largeTitleFont = UIFont(name: "PublicaPlay-Regular", size: 34) ?? .systemFont(ofSize: 34)
        let inlineTitleFont = UIFont(name: "PublicaPlay-Regular", size: 17) ?? .systemFont(ofSize: 17)

        UINavigationBar.appearance().largeTitleTextAttributes = [.font: largeTitleFont]
        UINavigationBar.appearance().titleTextAttributes = [.font: inlineTitleFont]

        // Tab bar item labels (if any appear)
        let tabBarFont = UIFont(name: "PublicaPlay-Regular", size: 10) ?? .systemFont(ofSize: 10)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabBarFont], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabBarFont], for: .selected)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                switch auth.state {
                case .loading:
                    Color(.systemBackground).ignoresSafeArea()
                case .unauthenticated:
                    OnboardingView()
                        .transition(.opacity)
                case .authenticated:
                    ContentView()
                        .transition(.opacity)
                        .task {
                            await WalletManager.shared.setupWallets()
                        }
                        .fullScreenCover(isPresented: $auth.showLoginSuccess) {
                            ThinkingView {
                                hasCompletedOnboarding = true
                                auth.showLoginSuccess = false
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: auth.state)
            .preferredColorScheme(theme.colorScheme)
            .onOpenURL { url in
                if url.scheme == "portlai" && url.host == "stop-tracking" {
                    LiveActivityManager.shared.stopTracking()
                }
            }
            .task {
                LiveActivityManager.shared.restoreExistingActivity()
            }
        }
    }
}
