//
//  ContentView.swift
//  ShadowGuard
//
//  Main tab-based navigation container
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunnelManager: TunnelManager
    @State private var selectedTab: Tab = .dashboard
    @State private var showDebugConsole = false
    
    enum Tab: String, CaseIterable {
        case dashboard = "Dashboard"
        case rules = "Rules"
        case logs = "Logs"
        case settings = "Settings"
        case about = "About"
        
        var icon: String {
            switch self {
            case .dashboard: return "shield.checkered"
            case .rules: return "list.bullet.rectangle"
            case .logs: return "doc.text.magnifyingglass"
            case .settings: return "gearshape.2"
            case .about: return "info.circle"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Animated gradient background
            AnimatedGradientBackground()
                .ignoresSafeArea()
            
            TabView(selection: $selectedTab) {
                DashboardView()
                    .tabItem {
                        Label(Tab.dashboard.rawValue, systemImage: Tab.dashboard.icon)
                    }
                    .tag(Tab.dashboard)
                
                RulesView()
                    .tabItem {
                        Label(Tab.rules.rawValue, systemImage: Tab.rules.icon)
                    }
                    .tag(Tab.rules)
                
                LogsView()
                    .tabItem {
                        Label(Tab.logs.rawValue, systemImage: Tab.logs.icon)
                    }
                    .tag(Tab.logs)
                
                SettingsView()
                    .tabItem {
                        Label(Tab.settings.rawValue, systemImage: Tab.settings.icon)
                    }
                    .tag(Tab.settings)
                
                AboutView()
                    .tabItem {
                        Label(Tab.about.rawValue, systemImage: Tab.about.icon)
                    }
                    .tag(Tab.about)
            }
            .tint(Color.neonCyan)
        }
        .onShake {
            showDebugConsole = true
        }
        .sheet(isPresented: $showDebugConsole) {
            DebugConsoleView()
        }
    }
}

// MARK: - Shake Gesture Detection
extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name(rawValue: "deviceDidShakeNotification")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
    }
}

struct DeviceShakeViewModifier: ViewModifier {
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
                action()
            }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.modifier(DeviceShakeViewModifier(action: action))
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
        .environmentObject(TunnelManager.shared)
        .environmentObject(FilterEngine.shared)
        .environmentObject(LogStore.shared)
}
