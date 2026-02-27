//
//  AppState.swift
//  ShadowGuard
//
//  Global application state management
//

import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    // MARK: - Published Properties
    @Published var isProtectionEnabled: Bool = false
    @Published var blockedToday: Int = 0
    @Published var blockedTotal: Int = 0
    @Published var savedBandwidth: Int64 = 0 // bytes
    @Published var topBlockedDomains: [BlockedDomain] = []
    @Published var protectionLevel: Double = 0.0 // 0.0 - 1.0
    @Published var isCAInstalled: Bool = false
    @Published var isCATrusted: Bool = false
    @Published var lastError: String?
    
    // MARK: - App Storage
    @AppStorage("totalBlockedCount") private var storedTotalBlocked: Int = 0
    @AppStorage("savedBandwidthBytes") private var storedSavedBandwidth: Int = 0
    @AppStorage("firstLaunchDate") private var firstLaunchDate: Double = Date().timeIntervalSince1970
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    
    private init() {
        blockedTotal = storedTotalBlocked
        savedBandwidth = Int64(storedSavedBandwidth)
        loadTopBlockedDomains()
        
        // Defer protection level calculation to avoid circular singleton access
        // (AppState.shared -> FilterEngine.shared during init)
        Task { @MainActor in
            self.calculateProtectionLevel()
        }
    }
    
    // MARK: - Methods
    func incrementBlocked(domain: String, savedBytes: Int64) {
        blockedToday += 1
        blockedTotal += 1
        storedTotalBlocked = blockedTotal
        
        savedBandwidth += savedBytes
        storedSavedBandwidth = Int(savedBandwidth)
        
        updateTopBlockedDomains(domain: domain)
        calculateProtectionLevel()
    }
    
    func resetDailyStats() {
        blockedToday = 0
    }
    
    func resetAllStats() {
        blockedToday = 0
        blockedTotal = 0
        savedBandwidth = 0
        storedTotalBlocked = 0
        storedSavedBandwidth = 0
        topBlockedDomains = []
        saveTopBlockedDomains()
    }
    
    private func updateTopBlockedDomains(domain: String) {
        if let index = topBlockedDomains.firstIndex(where: { $0.domain == domain }) {
            topBlockedDomains[index].count += 1
        } else {
            topBlockedDomains.append(BlockedDomain(domain: domain, count: 1))
        }
        
        topBlockedDomains.sort { $0.count > $1.count }
        if topBlockedDomains.count > 10 {
            topBlockedDomains = Array(topBlockedDomains.prefix(10))
        }
        
        saveTopBlockedDomains()
    }
    
    private func calculateProtectionLevel() {
        var level: Double = 0.0
        
        if isProtectionEnabled { level += 0.3 }
        if isCAInstalled { level += 0.2 }
        if isCATrusted { level += 0.2 }
        
        let filterEngine = FilterEngine.shared
        let enabledLists = filterEngine.builtInLists.filter { $0.isEnabled }.count
        let totalLists = filterEngine.builtInLists.count
        if totalLists > 0 {
            level += 0.3 * (Double(enabledLists) / Double(totalLists))
        }
        
        protectionLevel = min(level, 1.0)
    }
    
    private func loadTopBlockedDomains() {
        if let data = UserDefaults.standard.data(forKey: "topBlockedDomains"),
           let domains = try? JSONDecoder().decode([BlockedDomain].self, from: data) {
            topBlockedDomains = domains
        }
    }
    
    private func saveTopBlockedDomains() {
        if let data = try? JSONEncoder().encode(topBlockedDomains) {
            UserDefaults.standard.set(data, forKey: "topBlockedDomains")
        }
    }
    
    func updateProtectionStatus(enabled: Bool) {
        isProtectionEnabled = enabled
        calculateProtectionLevel()
    }
    
    func updateCAStatus(installed: Bool, trusted: Bool) {
        isCAInstalled = installed
        isCATrusted = trusted
        calculateProtectionLevel()
    }
}

// MARK: - Supporting Types
struct BlockedDomain: Identifiable, Codable, Equatable {
    let id: UUID
    let domain: String
    var count: Int
    
    init(domain: String, count: Int) {
        self.id = UUID()
        self.domain = domain
        self.count = count
    }
}
