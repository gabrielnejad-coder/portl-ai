//
//  ContentView.swift
//  Portl AI
//
//  Created by ardy on 2026-03-06.
//

import SwiftUI

/// Tab selection enum for programmatic navigation
enum AppTab: Int, Hashable, CaseIterable {
    case dashboard = 0
    case news = 1
    case search = 2
    case ai = 3
    case profile = 4
}

/// Root view with 5-tab Liquid Glass navigation for PORTL AI
struct ContentView: View {

    @State private var selectedTab: AppTab = .dashboard
    @State private var portfolioViewModel = PortfolioViewModel()
    @State private var auth = AuthManager.shared
    @State private var tabBarRevealed = false
    @State private var swipeDirection: Edge = .leading

    /// Atmosphere blue tab tint — AI tab glows purple, all others use brand blue
    private var tabTint: Color {
        selectedTab == .ai
            ? Color(hue: 0.75, saturation: 0.90, brightness: 1.0)
            : Color.atmPrimary
    }

    private var allTabs: [AppTab] { AppTab.allCases }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: .dashboard) {
                DashboardView()
                    .swipeTabGesture(current: $selectedTab, direction: $swipeDirection, tabs: allTabs)
            } label: {
                Image(systemName: "square.grid.2x2")
                    .scaleEffect(selectedTab == .dashboard ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedTab)
            }

            Tab(value: .news) {
                NewsView()
                    .swipeTabGesture(current: $selectedTab, direction: $swipeDirection, tabs: allTabs)
            } label: {
                Image("NewsIcon")
                    .scaleEffect(selectedTab == .news ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedTab)
            }

            Tab(value: .search) {
                SearchView()
                    .swipeTabGesture(current: $selectedTab, direction: $swipeDirection, tabs: allTabs)
            } label: {
                Image("SearchIcon")
                    .scaleEffect(selectedTab == .search ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedTab)
            }

            Tab(value: .ai) {
                AIView()
                    .swipeTabGesture(current: $selectedTab, direction: $swipeDirection, tabs: allTabs)
            } label: {
                Image(systemName: "bolt.fill")
                    .scaleEffect(selectedTab == .ai ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedTab)
            }

            Tab(value: .profile) {
                ProfileView()
                    .swipeTabGesture(current: $selectedTab, direction: $swipeDirection, tabs: allTabs)
            } label: {
                Image(systemName: "person.circle")
                    .scaleEffect(selectedTab == .profile ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedTab)
            }
        }
        .tint(tabTint)
        .environment(portfolioViewModel)
        .toolbar(tabBarRevealed ? .visible : .hidden, for: .tabBar)
        .onAppear {
            if !auth.showLoginSuccess {
                tabBarRevealed = true
            }
        }
        .onChange(of: auth.showLoginSuccess) { _, isShowing in
            if !isShowing {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05)) {
                    tabBarRevealed = true
                }
            }
        }
    }
}

// MARK: - Swipe Between Tabs

private struct SwipeTabGesture: ViewModifier {
    @Binding var current: AppTab
    @Binding var direction: Edge
    let tabs: [AppTab]

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 30, coordinateSpace: .global)
                    .onEnded { value in
                        // Only trigger on mostly-horizontal swipes
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                        guard let idx = tabs.firstIndex(of: current) else { return }

                        if value.translation.width < -50, idx < tabs.count - 1 {
                            direction = .trailing
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                current = tabs[idx + 1]
                            }
                        } else if value.translation.width > 50, idx > 0 {
                            direction = .leading
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                current = tabs[idx - 1]
                            }
                        }
                    }
            )
            .transition(.push(from: direction))
    }
}

extension View {
    func swipeTabGesture(current: Binding<AppTab>, direction: Binding<Edge>, tabs: [AppTab]) -> some View {
        modifier(SwipeTabGesture(current: current, direction: direction, tabs: tabs))
    }
}

#Preview {
    ContentView()
}
