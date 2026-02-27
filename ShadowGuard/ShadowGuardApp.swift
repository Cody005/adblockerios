//
//  ShadowGuardApp.swift
//  ShadowGuard
//
//  Created for personal use - MITM Ad Blocker
//  iOS 17.0+ | Swift 6
//

import SwiftUI

@main
struct ShadowGuardApp: App {
    @StateObject private var appState = AppState.shared
    @StateObject private var tunnelManager = TunnelManager.shared
    @StateObject private var filterEngine = FilterEngine.shared
    @StateObject private var logStore = LogStore.shared
    
    init() {
        configureAppearance()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(tunnelManager)
                .environmentObject(filterEngine)
                .environmentObject(logStore)
                .preferredColorScheme(.dark)
                .onAppear {
                    Task {
                        await tunnelManager.loadFromPreferences()
                    }
                }
        }
    }
    
    private func configureAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.shadowBackground)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(Color.shadowBackground)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    }
}
