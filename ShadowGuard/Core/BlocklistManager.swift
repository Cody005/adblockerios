//
//  BlocklistManager.swift
//  ShadowGuard
//
//  Manages blocklist downloading, caching, and auto-updates
//  Supports bundled lists and remote updates
//

import Foundation

@MainActor
final class BlocklistManager: ObservableObject {
    static let shared = BlocklistManager()
    
    // MARK: - Published Properties
    @Published var isUpdating: Bool = false
    @Published var lastUpdateDate: Date?
    @Published var updateProgress: Double = 0
    @Published var errorMessage: String?
    
    // MARK: - Properties
    private let appGroup = "group.com.shadowguard.app"
    private let fileManager = FileManager.default
    private var updateTask: Task<Void, Never>?
    
    // Auto-update interval (24 hours)
    private let updateInterval: TimeInterval = 86400
    
    // MARK: - Blocklist Sources
    struct BlocklistSource: Identifiable, Codable {
        let id: String
        var name: String
        var url: String
        let category: Category
        var isEnabled: Bool
        var lastUpdated: Date?
        var ruleCount: Int
        var isCustom: Bool
        
        enum Category: String, CaseIterable, Codable {
            case ads = "Ads"
            case privacy = "Privacy"
            case security = "Security"
            case social = "Social"
            case annoyances = "Annoyances"
            case custom = "Custom"
        }
        
        init(id: String, name: String, url: String, category: Category, isEnabled: Bool, ruleCount: Int, isCustom: Bool = false, lastUpdated: Date? = nil) {
            self.id = id
            self.name = name
            self.url = url
            self.category = category
            self.isEnabled = isEnabled
            self.ruleCount = ruleCount
            self.isCustom = isCustom
            self.lastUpdated = lastUpdated
        }
    }
    
    // Custom blocklist URLs added by user
    @Published var customSources: [BlocklistSource] = []
    
    var sources: [BlocklistSource] = [
        BlocklistSource(
            id: "easylist",
            name: "EasyList",
            url: "https://easylist.to/easylist/easylist.txt",
            category: .ads,
            isEnabled: true,
            ruleCount: 0
        ),
        BlocklistSource(
            id: "easyprivacy",
            name: "EasyPrivacy",
            url: "https://easylist.to/easylist/easyprivacy.txt",
            category: .privacy,
            isEnabled: true,
            ruleCount: 0
        ),
        BlocklistSource(
            id: "adguard-dns",
            name: "AdGuard DNS Filter",
            url: "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt",
            category: .ads,
            isEnabled: true,
            ruleCount: 0
        ),
        BlocklistSource(
            id: "stevenblack",
            name: "StevenBlack Hosts",
            url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
            category: .ads,
            isEnabled: true,
            ruleCount: 0
        ),
        BlocklistSource(
            id: "adguard-tracking",
            name: "AdGuard Tracking",
            url: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_3_Spyware/filter.txt",
            category: .privacy,
            isEnabled: false,
            ruleCount: 0
        ),
        BlocklistSource(
            id: "malware-domains",
            name: "Malware Domains",
            url: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_15_DnsFilter/filter.txt",
            category: .security,
            isEnabled: true,
            ruleCount: 0
        ),
        BlocklistSource(
            id: "fanboy-annoyances",
            name: "Fanboy Annoyances",
            url: "https://easylist.to/easylist/fanboy-annoyance.txt",
            category: .annoyances,
            isEnabled: false,
            ruleCount: 0
        ),
        BlocklistSource(
            id: "fanboy-social",
            name: "Fanboy Social",
            url: "https://easylist.to/easylist/fanboy-social.txt",
            category: .social,
            isEnabled: false,
            ruleCount: 0
        )
    ]
    
    // MARK: - Initialization
    private init() {
        loadSourceStates()
        loadCustomSources()
        loadLastUpdateDate()
        scheduleAutoUpdate()
        
        // First launch: download lists immediately if never updated before
        if lastUpdateDate == nil {
            Task { @MainActor in
                await updateAllLists()
            }
        }
    }
    
    /// All sources (built-in + custom)
    var allSources: [BlocklistSource] {
        sources + customSources
    }
    
    // MARK: - Public Methods
    
    /// Update all enabled blocklists
    func updateAllLists() async {
        guard !isUpdating else { return }
        
        isUpdating = true
        updateProgress = 0
        errorMessage = nil
        
        let enabledSources = allSources.filter { $0.isEnabled }
        let totalSources = Double(enabledSources.count)
        var completed = 0.0
        
        for source in enabledSources {
            do {
                try await downloadAndSaveList(source)
                completed += 1
                updateProgress = completed / totalSources
            } catch {
                NSLog("[BlocklistManager] Failed to update \(source.name): \(error)")
                errorMessage = "Failed to update \(source.name)"
            }
        }
        
        lastUpdateDate = Date()
        saveLastUpdateDate()
        saveSourceStates()
        saveCustomSources()
        
        // Notify tunnel to reload rules
        notifyTunnelToReload()
        
        isUpdating = false
        updateProgress = 1.0
    }
    
    /// Toggle a blocklist source
    func toggleSource(_ sourceId: String) {
        if let index = sources.firstIndex(where: { $0.id == sourceId }) {
            sources[index].isEnabled.toggle()
            saveSourceStates()
            notifyTunnelToReload()
        } else if let index = customSources.firstIndex(where: { $0.id == sourceId }) {
            customSources[index].isEnabled.toggle()
            saveCustomSources()
            notifyTunnelToReload()
        }
    }
    
    /// Add a custom blocklist URL
    func addCustomBlocklist(name: String, url: String) {
        let id = "custom-\(UUID().uuidString.prefix(8))"
        let source = BlocklistSource(
            id: id,
            name: name,
            url: url,
            category: .custom,
            isEnabled: true,
            ruleCount: 0,
            isCustom: true
        )
        customSources.append(source)
        saveCustomSources()
        
        // Download immediately
        Task { @MainActor in
            do {
                try await downloadAndSaveList(source)
                notifyTunnelToReload()
            } catch {
                NSLog("[BlocklistManager] Failed to download custom list: \(error)")
            }
        }
    }
    
    /// Remove a custom blocklist
    func removeCustomBlocklist(_ sourceId: String) {
        customSources.removeAll { $0.id == sourceId }
        saveCustomSources()
        
        // Delete the file
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            let fileURL = containerURL.appendingPathComponent("FilterLists/\(sourceId).txt")
            try? fileManager.removeItem(at: fileURL)
        }
        
        notifyTunnelToReload()
    }
    
    /// Check if update is needed
    func needsUpdate() -> Bool {
        guard let lastUpdate = lastUpdateDate else { return true }
        return Date().timeIntervalSince(lastUpdate) > updateInterval
    }
    
    /// Get total rule count
    var totalRuleCount: Int {
        allSources.filter { $0.isEnabled }.reduce(0) { $0 + $1.ruleCount }
    }
    
    // MARK: - Private Methods
    
    private func downloadAndSaveList(_ source: BlocklistSource) async throws {
        guard let url = URL(string: source.url) else {
            throw BlocklistError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BlocklistError.downloadFailed
        }
        
        guard let content = String(data: data, encoding: .utf8) else {
            throw BlocklistError.invalidContent
        }
        
        // Save to app group container
        try saveListToAppGroup(source.id, content: content)
        
        // Update rule count
        let ruleCount = countRules(in: content)
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            sources[index].ruleCount = ruleCount
            sources[index].lastUpdated = Date()
        }
    }
    
    private func saveListToAppGroup(_ id: String, content: String) throws {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw BlocklistError.appGroupNotAvailable
        }
        
        let listsDir = containerURL.appendingPathComponent("FilterLists", isDirectory: true)
        
        if !fileManager.fileExists(atPath: listsDir.path) {
            try fileManager.createDirectory(at: listsDir, withIntermediateDirectories: true)
        }
        
        let fileURL = listsDir.appendingPathComponent("\(id).txt")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func countRules(in content: String) -> Int {
        let lines = content.components(separatedBy: .newlines)
        return lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty &&
                   !trimmed.hasPrefix("!") &&
                   !trimmed.hasPrefix("#") &&
                   !trimmed.hasPrefix("[")
        }.count
    }
    
    private func notifyTunnelToReload() {
        // Save flag for tunnel to check
        if let userDefaults = UserDefaults(suiteName: appGroup) {
            userDefaults.set(true, forKey: "needsRuleReload")
            userDefaults.set(Date().timeIntervalSince1970, forKey: "lastRuleUpdate")
        }
    }
    
    // MARK: - Persistence
    
    private func saveSourceStates() {
        var states: [String: [String: Any]] = [:]
        for source in sources {
            states[source.id] = [
                "isEnabled": source.isEnabled,
                "ruleCount": source.ruleCount,
                "lastUpdated": source.lastUpdated?.timeIntervalSince1970 ?? 0
            ]
        }
        
        UserDefaults.standard.set(states, forKey: "blocklistSourceStates")
        
        // Also save to app group for tunnel
        if let userDefaults = UserDefaults(suiteName: appGroup) {
            let enabledStates = sources.reduce(into: [String: Bool]()) { result, source in
                result[source.id] = source.isEnabled
            }
            userDefaults.set(enabledStates, forKey: "filterListStates")
        }
    }
    
    private func loadSourceStates() {
        guard let states = UserDefaults.standard.dictionary(forKey: "blocklistSourceStates") as? [String: [String: Any]] else {
            return
        }
        
        for (id, state) in states {
            if let index = sources.firstIndex(where: { $0.id == id }) {
                sources[index].isEnabled = state["isEnabled"] as? Bool ?? false
                sources[index].ruleCount = state["ruleCount"] as? Int ?? 0
                if let timestamp = state["lastUpdated"] as? TimeInterval, timestamp > 0 {
                    sources[index].lastUpdated = Date(timeIntervalSince1970: timestamp)
                }
            }
        }
    }
    
    private func saveLastUpdateDate() {
        UserDefaults.standard.set(lastUpdateDate, forKey: "blocklistLastUpdate")
    }
    
    private func loadLastUpdateDate() {
        lastUpdateDate = UserDefaults.standard.object(forKey: "blocklistLastUpdate") as? Date
    }
    
    // MARK: - Auto-Update
    
    private func scheduleAutoUpdate() {
        updateTask?.cancel()
        
        updateTask = Task { @MainActor in
            while !Task.isCancelled {
                if needsUpdate() {
                    await updateAllLists()
                }
                
                // Check every hour
                try? await Task.sleep(nanoseconds: 3600 * 1_000_000_000)
            }
        }
    }
    
    // MARK: - Custom Sources Persistence
    
    private func saveCustomSources() {
        if let data = try? JSONEncoder().encode(customSources) {
            UserDefaults.standard.set(data, forKey: "customBlocklistSources")
            
            // Also save to app group for tunnel
            if let userDefaults = UserDefaults(suiteName: appGroup) {
                userDefaults.set(data, forKey: "customBlocklistSources")
            }
        }
    }
    
    private func loadCustomSources() {
        if let data = UserDefaults.standard.data(forKey: "customBlocklistSources"),
           let sources = try? JSONDecoder().decode([BlocklistSource].self, from: data) {
            customSources = sources
        }
    }
}

// MARK: - Errors
enum BlocklistError: LocalizedError {
    case invalidURL
    case downloadFailed
    case invalidContent
    case appGroupNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid blocklist URL"
        case .downloadFailed: return "Failed to download blocklist"
        case .invalidContent: return "Invalid blocklist content"
        case .appGroupNotAvailable: return "App group not available"
        }
    }
}
