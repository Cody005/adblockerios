//
//  TunnelManager.swift
//  ShadowGuard
//
//  Manages the VPN tunnel configuration and lifecycle
//  Updated for SNI-based blocking (no MITM required)
//

@preconcurrency import Foundation
@preconcurrency import NetworkExtension

@MainActor
final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()
    
    // MARK: - Published Properties
    @Published var tunnelStatus: NEVPNStatus = .disconnected
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var connectionDate: Date?
    
    // MARK: - Private Properties
    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    
    // MARK: - Constants
    private let tunnelBundleIdentifier = "com.shadowguard.app.tunnel"
    private let tunnelDescription = "ShadowGuard Ad Blocker"
    private let appGroup = "group.com.shadowguard.app"
    
    var isConnected: Bool {
        tunnelStatus == .connected
    }
    
    var statusDescription: String {
        switch tunnelStatus {
        case .invalid: return "Invalid"
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Protected"
        case .reasserting: return "Reconnecting..."
        case .disconnecting: return "Disconnecting..."
        @unknown default: return "Unknown"
        }
    }
    
    private init() {}
    
    deinit {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Public Methods
    func loadFromPreferences() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            
            if let existingManager = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == tunnelBundleIdentifier
            }) {
                manager = existingManager
                tunnelStatus = existingManager.connection.status
                observeStatusChanges()
                LogStore.shared.addLog(.info, "Loaded existing tunnel configuration")
            } else {
                LogStore.shared.addLog(.info, "No existing tunnel configuration found")
            }
        } catch {
            errorMessage = "Failed to load tunnel: \(error.localizedDescription)"
            LogStore.shared.addLog(.error, "Failed to load tunnel: \(error.localizedDescription)")
        }
    }
    
    func setupTunnel() async throws {
        isLoading = true
        defer { isLoading = false }
        
        let newManager = NETunnelProviderManager()
        
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = tunnelBundleIdentifier
        tunnelProtocol.serverAddress = "ShadowGuard Local"
        tunnelProtocol.providerConfiguration = [
            "proxyPort": 8899,
            "logLevel": "debug"
        ]
        
        newManager.protocolConfiguration = tunnelProtocol
        newManager.localizedDescription = tunnelDescription
        newManager.isEnabled = true
        
        // Configure on-demand rules (optional - always on when enabled)
        let connectRule = NEOnDemandRuleConnect()
        connectRule.interfaceTypeMatch = .any
        newManager.onDemandRules = [connectRule]
        newManager.isOnDemandEnabled = false // User controls manually
        
        do {
            try await newManager.saveToPreferences()
            try await newManager.loadFromPreferences()
            
            manager = newManager
            observeStatusChanges()
            
            LogStore.shared.addLog(.info, "Tunnel configuration saved successfully")
        } catch {
            errorMessage = "Failed to setup tunnel: \(error.localizedDescription)"
            LogStore.shared.addLog(.error, "Failed to setup tunnel: \(error.localizedDescription)")
            throw error
        }
    }
    
    func startTunnel() async throws {
        guard let manager = manager else {
            try await setupTunnel()
            try await startTunnel()
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Ensure manager is enabled
            if !manager.isEnabled {
                manager.isEnabled = true
                try await manager.saveToPreferences()
            }
            
            let session = manager.connection as? NETunnelProviderSession
            try session?.startTunnel(options: [
                "startReason": "userInitiated" as NSString
            ])
            
            connectionDate = Date()
            LogStore.shared.addLog(.info, "Tunnel start requested")
            
            AppState.shared.updateProtectionStatus(enabled: true)
        } catch {
            errorMessage = "Failed to start tunnel: \(error.localizedDescription)"
            LogStore.shared.addLog(.error, "Failed to start tunnel: \(error.localizedDescription)")
            throw error
        }
    }
    
    func stopTunnel() {
        guard let manager = manager else { return }
        
        manager.connection.stopVPNTunnel()
        connectionDate = nil
        LogStore.shared.addLog(.info, "Tunnel stop requested")
        
        Task { @MainActor in
            AppState.shared.updateProtectionStatus(enabled: false)
        }
    }
    
    func toggleTunnel() async throws {
        if isConnected {
            stopTunnel()
        } else {
            try await startTunnel()
        }
    }
    
    func removeTunnel() async throws {
        guard let manager = manager else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await manager.removeFromPreferences()
            self.manager = nil
            tunnelStatus = .disconnected
            LogStore.shared.addLog(.info, "Tunnel configuration removed")
        } catch {
            errorMessage = "Failed to remove tunnel: \(error.localizedDescription)"
            LogStore.shared.addLog(.error, "Failed to remove tunnel: \(error.localizedDescription)")
            throw error
        }
    }
    
    func sendMessageToTunnel(_ message: [String: Any]) async throws -> Data? {
        guard let session = manager?.connection as? NETunnelProviderSession else {
            throw TunnelError.notConnected
        }
        
        let data = try JSONSerialization.data(withJSONObject: message)
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(data) { response in
                    continuation.resume(returning: response)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Send a simple command to the tunnel (pause, resume, reloadRules)
    func sendCommand(_ command: String) async throws {
        _ = try await sendMessageToTunnel(["command": command])
    }
    
    /// Get stats from the tunnel
    func getStats() async throws -> [String: Any]? {
        guard let data = try await sendMessageToTunnel(["command": "getStats"]) else {
            return nil
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    
    // MARK: - Private Methods
    private func observeStatusChanges() {
        guard let manager = manager else { return }
        
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.tunnelStatus = manager.connection.status
                
                switch self.tunnelStatus {
                case .connected:
                    AppState.shared.updateProtectionStatus(enabled: true)
                    LogStore.shared.addLog(.info, "Tunnel connected")
                case .disconnected:
                    AppState.shared.updateProtectionStatus(enabled: false)
                    LogStore.shared.addLog(.info, "Tunnel disconnected")
                case .connecting:
                    LogStore.shared.addLog(.info, "Tunnel connecting...")
                case .disconnecting:
                    LogStore.shared.addLog(.info, "Tunnel disconnecting...")
                case .reasserting:
                    LogStore.shared.addLog(.warning, "Tunnel reasserting connection...")
                default:
                    break
                }
            }
        }
    }
}

// MARK: - Errors
enum TunnelError: LocalizedError {
    case notConfigured
    case notConnected
    case configurationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Tunnel is not configured"
        case .notConnected:
            return "Tunnel is not connected"
        case .configurationFailed(let reason):
            return "Configuration failed: \(reason)"
        }
    }
}
