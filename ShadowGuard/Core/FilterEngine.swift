//
//  FilterEngine.swift
//  ShadowGuard
//
//  Powerful filtering engine with AdBlock Plus & uBlock Origin syntax support
//

import Foundation
import Combine

@MainActor
final class FilterEngine: ObservableObject {
    static let shared = FilterEngine()
    
    // MARK: - Published Properties
    @Published var builtInLists: [FilterList] = []
    @Published var customRules: [CustomRule] = []
    @Published var isLoading: Bool = false
    @Published var lastUpdateDate: Date?
    
    // MARK: - Private Properties
    private var compiledRules: [CompiledRule] = []
    private var whitelistRules: [CompiledRule] = []
    private var redirectRules: [RedirectRule] = []
    private var cosmeticRules: [CosmeticRule] = []
    
    private let rulesQueue = DispatchQueue(label: "com.shadowguard.rules", qos: .userInitiated)
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    private init() {
        setupBuiltInLists()
        loadCustomRules()
        Task {
            await compileAllRules()
        }
    }
    
    // MARK: - Built-in Lists
    private func setupBuiltInLists() {
        builtInLists = [
            FilterList(
                id: "easylist",
                name: "EasyList",
                description: "Primary filter list for blocking ads",
                url: "https://easylist.to/easylist/easylist.txt",
                category: .ads,
                isEnabled: true
            ),
            FilterList(
                id: "easyprivacy",
                name: "EasyPrivacy",
                description: "Blocks tracking scripts and trackers",
                url: "https://easylist.to/easylist/easyprivacy.txt",
                category: .privacy,
                isEnabled: true
            ),
            FilterList(
                id: "adguard-base",
                name: "AdGuard Base",
                description: "AdGuard's comprehensive ad blocking list",
                url: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_2_Base/filter.txt",
                category: .ads,
                isEnabled: true
            ),
            FilterList(
                id: "adguard-tracking",
                name: "AdGuard Tracking Protection",
                description: "Blocks online trackers",
                url: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_3_Spyware/filter.txt",
                category: .privacy,
                isEnabled: false
            ),
            FilterList(
                id: "adguard-annoyances",
                name: "AdGuard Annoyances",
                description: "Blocks cookie notices, popups, etc.",
                url: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_14_Annoyances/filter.txt",
                category: .annoyances,
                isEnabled: false
            ),
            FilterList(
                id: "stevenblack",
                name: "StevenBlack Hosts",
                description: "Unified hosts file with multiple extensions",
                url: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
                category: .ads,
                isEnabled: true
            ),
            FilterList(
                id: "malware-domains",
                name: "Malware Domain List",
                description: "Blocks known malware domains",
                url: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_15_DnsFilter/filter.txt",
                category: .security,
                isEnabled: true
            ),
            FilterList(
                id: "fanboy-social",
                name: "Fanboy's Social Blocking",
                description: "Blocks social media widgets",
                url: "https://easylist.to/easylist/fanboy-social.txt",
                category: .social,
                isEnabled: false
            )
        ]
        
        loadListStates()
    }
    
    // MARK: - Rule Matching
    func shouldBlock(url: String, domain: String, resourceType: ResourceType = .other) -> FilterResult {
        // Check whitelist first
        for rule in whitelistRules {
            if rule.matches(url: url, domain: domain, resourceType: resourceType) {
                return .allowed(reason: "Whitelist: \(rule.originalRule)")
            }
        }
        
        // Check redirect rules
        for rule in redirectRules {
            if rule.matches(url: url, domain: domain) {
                return .redirect(to: rule.redirectTo, reason: rule.originalRule)
            }
        }
        
        // Check block rules
        for rule in compiledRules {
            if rule.matches(url: url, domain: domain, resourceType: resourceType) {
                return .blocked(reason: rule.originalRule)
            }
        }
        
        return .allowed(reason: "No matching rule")
    }
    
    func getCosmeticRules(for domain: String) -> [String] {
        return cosmeticRules
            .filter { $0.appliesToDomain(domain) }
            .map { $0.selector }
    }
    
    // MARK: - List Management
    func toggleList(_ list: FilterList) {
        if let index = builtInLists.firstIndex(where: { $0.id == list.id }) {
            builtInLists[index].isEnabled.toggle()
            saveListStates()
            Task {
                await compileAllRules()
            }
        }
    }
    
    func updateAllLists() async {
        isLoading = true
        defer { isLoading = false }
        
        for list in builtInLists where list.isEnabled {
            await downloadList(list)
        }
        
        lastUpdateDate = Date()
        await compileAllRules()
        
        LogStore.shared.addLog(.info, "Filter lists updated")
    }
    
    func downloadList(_ list: FilterList) async {
        guard let url = URL(string: list.url) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let content = String(data: data, encoding: .utf8) {
                saveListContent(list.id, content: content)
                
                if let index = builtInLists.firstIndex(where: { $0.id == list.id }) {
                    builtInLists[index].lastUpdated = Date()
                    builtInLists[index].ruleCount = content.components(separatedBy: .newlines)
                        .filter { !$0.isEmpty && !$0.hasPrefix("!") && !$0.hasPrefix("[") }
                        .count
                }
            }
        } catch {
            LogStore.shared.addLog(.error, "Failed to download \(list.name): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Custom Rules
    func addCustomRule(_ rule: CustomRule) {
        customRules.append(rule)
        saveCustomRules()
        Task {
            await compileAllRules()
        }
    }
    
    func updateCustomRule(_ rule: CustomRule) {
        if let index = customRules.firstIndex(where: { $0.id == rule.id }) {
            customRules[index] = rule
            saveCustomRules()
            Task {
                await compileAllRules()
            }
        }
    }
    
    func deleteCustomRule(_ rule: CustomRule) {
        customRules.removeAll { $0.id == rule.id }
        saveCustomRules()
        Task {
            await compileAllRules()
        }
    }
    
    func testRule(_ ruleText: String, against url: String) -> RuleTestResult {
        guard let compiled = parseRule(ruleText) else {
            return RuleTestResult(matches: false, error: "Invalid rule syntax")
        }
        
        let domain = URL(string: url)?.host ?? ""
        let matches = compiled.matches(url: url, domain: domain, resourceType: .other)
        
        return RuleTestResult(matches: matches, error: nil)
    }
    
    // MARK: - Rule Compilation
    func compileAllRules() async {
        await withCheckedContinuation { continuation in
            rulesQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                var newCompiledRules: [CompiledRule] = []
                var newWhitelistRules: [CompiledRule] = []
                var newRedirectRules: [RedirectRule] = []
                var newCosmeticRules: [CosmeticRule] = []
                
                // Parse built-in lists
                for list in self.builtInLists where list.isEnabled {
                    if let content = self.loadListContent(list.id) {
                        let parsed = self.parseFilterList(content)
                        newCompiledRules.append(contentsOf: parsed.blockRules)
                        newWhitelistRules.append(contentsOf: parsed.whitelistRules)
                        newCosmeticRules.append(contentsOf: parsed.cosmeticRules)
                    }
                }
                
                // Parse custom rules
                for rule in self.customRules where rule.isEnabled {
                    switch rule.type {
                    case .block:
                        if let compiled = self.parseRule(rule.pattern) {
                            newCompiledRules.append(compiled)
                        }
                    case .allow:
                        if let compiled = self.parseRule(rule.pattern) {
                            newWhitelistRules.append(compiled)
                        }
                    case .redirect:
                        if let redirect = self.parseRedirectRule(rule.pattern, to: rule.redirectTarget ?? "0.0.0.0") {
                            newRedirectRules.append(redirect)
                        }
                    }
                }
                
                Task { @MainActor in
                    self.compiledRules = newCompiledRules
                    self.whitelistRules = newWhitelistRules
                    self.redirectRules = newRedirectRules
                    self.cosmeticRules = newCosmeticRules
                    
                    LogStore.shared.addLog(.info, "Compiled \(newCompiledRules.count) block rules, \(newWhitelistRules.count) whitelist rules")
                }
                
                continuation.resume()
            }
        }
    }
    
    // MARK: - Parsing
    private func parseFilterList(_ content: String) -> ParsedList {
        var blockRules: [CompiledRule] = []
        var whitelistRules: [CompiledRule] = []
        var cosmeticRules: [CosmeticRule] = []
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and metadata
            if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("[") || trimmed.hasPrefix("#") && !trimmed.contains("##") {
                continue
            }
            
            // Hosts file format (StevenBlack)
            if trimmed.hasPrefix("0.0.0.0 ") || trimmed.hasPrefix("127.0.0.1 ") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2 {
                    let domain = String(parts[1])
                    if domain != "localhost" && !domain.hasPrefix("#") {
                        if let rule = parseRule("||" + domain + "^") {
                            blockRules.append(rule)
                        }
                    }
                }
                continue
            }
            
            // Cosmetic rules (element hiding)
            if trimmed.contains("##") || trimmed.contains("#@#") || trimmed.contains("#?#") {
                if let cosmetic = parseCosmeticRule(trimmed) {
                    cosmeticRules.append(cosmetic)
                }
                continue
            }
            
            // Whitelist rules
            if trimmed.hasPrefix("@@") {
                let ruleText = String(trimmed.dropFirst(2))
                if let rule = parseRule(ruleText) {
                    whitelistRules.append(rule)
                }
                continue
            }
            
            // Regular block rules
            if let rule = parseRule(trimmed) {
                blockRules.append(rule)
            }
        }
        
        return ParsedList(blockRules: blockRules, whitelistRules: whitelistRules, cosmeticRules: cosmeticRules)
    }
    
    private func parseRule(_ ruleText: String) -> CompiledRule? {
        var pattern = ruleText
        var options = RuleOptions()
        
        // Parse options (after $)
        if let dollarIndex = pattern.lastIndex(of: "$") {
            let optionsString = String(pattern[pattern.index(after: dollarIndex)...])
            pattern = String(pattern[..<dollarIndex])
            options = parseOptions(optionsString)
        }
        
        // Convert AdBlock pattern to regex
        guard let regex = convertToRegex(pattern) else { return nil }
        
        return CompiledRule(
            originalRule: ruleText,
            regex: regex,
            options: options
        )
    }
    
    private func parseOptions(_ optionsString: String) -> RuleOptions {
        var options = RuleOptions()
        let parts = optionsString.split(separator: ",")
        
        for part in parts {
            let option = String(part).trimmingCharacters(in: .whitespaces)
            
            if option.hasPrefix("domain=") {
                let domains = String(option.dropFirst(7)).split(separator: "|")
                for domain in domains {
                    let d = String(domain)
                    if d.hasPrefix("~") {
                        options.excludedDomains.append(String(d.dropFirst()))
                    } else {
                        options.includedDomains.append(d)
                    }
                }
            } else if option == "third-party" || option == "3p" {
                options.thirdParty = true
            } else if option == "~third-party" || option == "~3p" || option == "first-party" || option == "1p" {
                options.firstParty = true
            } else if option == "script" {
                options.resourceTypes.insert(.script)
            } else if option == "image" {
                options.resourceTypes.insert(.image)
            } else if option == "stylesheet" || option == "css" {
                options.resourceTypes.insert(.stylesheet)
            } else if option == "xmlhttprequest" || option == "xhr" {
                options.resourceTypes.insert(.xhr)
            } else if option == "document" || option == "doc" {
                options.resourceTypes.insert(.document)
            } else if option == "important" {
                options.important = true
            }
        }
        
        return options
    }
    
    private func convertToRegex(_ pattern: String) -> NSRegularExpression? {
        var regexPattern = pattern
        
        // Handle special AdBlock syntax
        if regexPattern.hasPrefix("||") {
            // Domain anchor: matches domain and subdomains
            regexPattern = String(regexPattern.dropFirst(2))
            regexPattern = "^https?://([a-z0-9-]+\\.)*" + NSRegularExpression.escapedPattern(for: regexPattern)
        } else if regexPattern.hasPrefix("|") {
            // Start anchor
            regexPattern = "^" + NSRegularExpression.escapedPattern(for: String(regexPattern.dropFirst()))
        } else if regexPattern.hasSuffix("|") {
            // End anchor
            regexPattern = NSRegularExpression.escapedPattern(for: String(regexPattern.dropLast())) + "$"
        } else if regexPattern.hasPrefix("/") && regexPattern.hasSuffix("/") && regexPattern.count > 2 {
            // Already a regex
            regexPattern = String(regexPattern.dropFirst().dropLast())
        } else {
            regexPattern = NSRegularExpression.escapedPattern(for: regexPattern)
        }
        
        // Convert wildcards
        regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: ".*")
        
        // Convert separator (^)
        regexPattern = regexPattern.replacingOccurrences(of: "\\^", with: "([/?#]|$)")
        
        do {
            return try NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive])
        } catch {
            return nil
        }
    }
    
    private func parseCosmeticRule(_ ruleText: String) -> CosmeticRule? {
        // Element hiding: domain##selector or ##selector
        if let range = ruleText.range(of: "##") {
            let domains = String(ruleText[..<range.lowerBound])
            let selector = String(ruleText[range.upperBound...])
            
            let domainList = domains.isEmpty ? [] : domains.split(separator: ",").map { String($0) }
            
            return CosmeticRule(
                originalRule: ruleText,
                selector: selector,
                domains: domainList,
                isException: false
            )
        }
        
        // Exception: domain#@#selector
        if let range = ruleText.range(of: "#@#") {
            let domains = String(ruleText[..<range.lowerBound])
            let selector = String(ruleText[range.upperBound...])
            
            let domainList = domains.isEmpty ? [] : domains.split(separator: ",").map { String($0) }
            
            return CosmeticRule(
                originalRule: ruleText,
                selector: selector,
                domains: domainList,
                isException: true
            )
        }
        
        return nil
    }
    
    private func parseRedirectRule(_ pattern: String, to target: String) -> RedirectRule? {
        guard let regex = convertToRegex(pattern) else { return nil }
        
        return RedirectRule(
            originalRule: pattern,
            regex: regex,
            redirectTo: target
        )
    }
    
    // MARK: - Persistence
    private func saveListStates() {
        let states = builtInLists.reduce(into: [String: Bool]()) { result, list in
            result[list.id] = list.isEnabled
        }
        UserDefaults.standard.set(states, forKey: "filterListStates")
    }
    
    private func loadListStates() {
        guard let states = UserDefaults.standard.dictionary(forKey: "filterListStates") as? [String: Bool] else { return }
        
        for (id, enabled) in states {
            if let index = builtInLists.firstIndex(where: { $0.id == id }) {
                builtInLists[index].isEnabled = enabled
            }
        }
    }
    
    private func saveListContent(_ id: String, content: String) {
        guard let url = getListFileURL(id) else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func loadListContent(_ id: String) -> String? {
        guard let url = getListFileURL(id) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
    
    private func getListFileURL(_ id: String) -> URL? {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let listsDir = documentsURL.appendingPathComponent("FilterLists", isDirectory: true)
        
        if !fileManager.fileExists(atPath: listsDir.path) {
            try? fileManager.createDirectory(at: listsDir, withIntermediateDirectories: true)
        }
        
        return listsDir.appendingPathComponent("\(id).txt")
    }
    
    private func saveCustomRules() {
        if let data = try? JSONEncoder().encode(customRules) {
            UserDefaults.standard.set(data, forKey: "customFilterRules")
        }
    }
    
    private func loadCustomRules() {
        if let data = UserDefaults.standard.data(forKey: "customFilterRules"),
           let rules = try? JSONDecoder().decode([CustomRule].self, from: data) {
            customRules = rules
        }
    }
    
    func exportRules() -> String {
        return customRules.map { rule in
            var line = ""
            switch rule.type {
            case .allow: line = "@@"
            case .block: line = ""
            case .redirect: line = ""
            }
            line += rule.pattern
            if let comment = rule.comment, !comment.isEmpty {
                line += " ! \(comment)"
            }
            return line
        }.joined(separator: "\n")
    }
    
    func importRules(_ content: String) {
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("!") { continue }
            
            var type: CustomRule.RuleType = .block
            var pattern = trimmed
            
            if pattern.hasPrefix("@@") {
                type = .allow
                pattern = String(pattern.dropFirst(2))
            }
            
            let rule = CustomRule(
                pattern: pattern,
                type: type,
                isEnabled: true,
                comment: nil
            )
            
            if !customRules.contains(where: { $0.pattern == rule.pattern }) {
                customRules.append(rule)
            }
        }
        
        saveCustomRules()
        Task {
            await compileAllRules()
        }
    }
}

// MARK: - Supporting Types
struct FilterList: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let url: String
    let category: FilterCategory
    var isEnabled: Bool
    var lastUpdated: Date?
    var ruleCount: Int = 0
    
    enum FilterCategory: String, CaseIterable {
        case ads = "Ads"
        case privacy = "Privacy"
        case security = "Security"
        case social = "Social"
        case annoyances = "Annoyances"
        case custom = "Custom"
    }
}

struct CustomRule: Identifiable, Codable, Equatable {
    let id: UUID
    var pattern: String
    var type: RuleType
    var isEnabled: Bool
    var comment: String?
    var redirectTarget: String?
    
    init(pattern: String, type: RuleType, isEnabled: Bool = true, comment: String? = nil, redirectTarget: String? = nil) {
        self.id = UUID()
        self.pattern = pattern
        self.type = type
        self.isEnabled = isEnabled
        self.comment = comment
        self.redirectTarget = redirectTarget
    }
    
    enum RuleType: String, Codable, CaseIterable {
        case block = "Block"
        case allow = "Allow"
        case redirect = "Redirect"
    }
}

struct FilterResult: Equatable {
    enum ResultType: Equatable {
        case blocked
        case allowed
        case redirect(String)
    }
    
    let type: ResultType
    let reason: String
    
    static func blocked(reason: String) -> FilterResult {
        FilterResult(type: .blocked, reason: reason)
    }
    
    static func allowed(reason: String) -> FilterResult {
        FilterResult(type: .allowed, reason: reason)
    }
    
    static func redirect(to: String, reason: String) -> FilterResult {
        FilterResult(type: .redirect(to), reason: reason)
    }
    
    var isBlocked: Bool {
        if case .blocked = type { return true }
        return false
    }
}

struct RuleTestResult {
    let matches: Bool
    let error: String?
}

enum ResourceType: String, CaseIterable {
    case script
    case image
    case stylesheet
    case xhr
    case document
    case font
    case media
    case websocket
    case other
}

// MARK: - Internal Types
private struct ParsedList {
    let blockRules: [CompiledRule]
    let whitelistRules: [CompiledRule]
    let cosmeticRules: [CosmeticRule]
}

private struct CompiledRule {
    let originalRule: String
    let regex: NSRegularExpression
    let options: RuleOptions
    
    func matches(url: String, domain: String, resourceType: ResourceType) -> Bool {
        // Check domain restrictions
        if !options.includedDomains.isEmpty {
            let domainMatches = options.includedDomains.contains { includedDomain in
                domain == includedDomain || domain.hasSuffix("." + includedDomain)
            }
            if !domainMatches { return false }
        }
        
        if options.excludedDomains.contains(where: { domain == $0 || domain.hasSuffix("." + $0) }) {
            return false
        }
        
        // Check resource type
        if !options.resourceTypes.isEmpty && !options.resourceTypes.contains(resourceType) {
            return false
        }
        
        // Check URL pattern
        let range = NSRange(url.startIndex..., in: url)
        return regex.firstMatch(in: url, options: [], range: range) != nil
    }
}

private struct RuleOptions {
    var includedDomains: [String] = []
    var excludedDomains: [String] = []
    var resourceTypes: Set<ResourceType> = []
    var thirdParty: Bool = false
    var firstParty: Bool = false
    var important: Bool = false
}

private struct RedirectRule {
    let originalRule: String
    let regex: NSRegularExpression
    let redirectTo: String
    
    func matches(url: String, domain: String) -> Bool {
        let range = NSRange(url.startIndex..., in: url)
        return regex.firstMatch(in: url, options: [], range: range) != nil
    }
}

private struct CosmeticRule {
    let originalRule: String
    let selector: String
    let domains: [String]
    let isException: Bool
    
    func appliesToDomain(_ domain: String) -> Bool {
        if domains.isEmpty { return !isException }
        
        for d in domains {
            if d.hasPrefix("~") {
                let excludedDomain = String(d.dropFirst())
                if domain == excludedDomain || domain.hasSuffix("." + excludedDomain) {
                    return isException
                }
            } else {
                if domain == d || domain.hasSuffix("." + d) {
                    return !isException
                }
            }
        }
        
        return domains.allSatisfy { $0.hasPrefix("~") } ? !isException : isException
    }
}
