//
//  DNSProxyProvider.swift
//  ShadowGuardDNSProxy
//
//  DNS Proxy Provider for efficient DNS-level ad blocking
//  Resolves blocked domains to 0.0.0.0 without external servers
//

@preconcurrency import NetworkExtension

import Foundation

final class DNSProxyProvider: NEDNSProxyProvider, @unchecked Sendable {
    
    // MARK: - Properties
    private let appGroup = "group.com.shadowguard.app"
    private var domainMatcher: HighPerformanceDomainMatcher?
    private var isRunning = false
    
    private var blockedCount: Int = 0
    private var totalQueries: Int = 0
    private let statsLock = NSLock()
    
    // MARK: - Lifecycle
    
    override func startProxy(options: [String: Any]? = nil, completionHandler: @escaping @Sendable (Error?) -> Void) {
        log("Starting DNS Proxy Provider")
        
        // Load blocklists
        Task { [weak self, completionHandler] in
            await self?.loadBlocklists()
            self?.isRunning = true
            self?.log("DNS Proxy started with \(self?.domainMatcher?.totalDomains ?? 0) blocked domains")
            completionHandler(nil)
        }
    }
    
    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log("Stopping DNS Proxy with reason: \(reason.rawValue)")
        isRunning = false
        
        // Save stats
        saveStats()
        
        completionHandler()
    }
    
    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        // DNS Proxy doesn't use this - uses handleNewUDPFlow instead
        return false
    }
    
    @available(iOS, deprecated: 18.0)
    @available(macOS, deprecated: 15.0)
    override func handleNewUDPFlow(_ flow: NEAppProxyUDPFlow, initialRemoteEndpoint remoteEndpoint: NWEndpoint) -> Bool {
        guard isRunning else { return false }
        
        // Check if this is DNS traffic (port 53)
        guard isDNSEndpoint(remoteEndpoint) else {
            return false
        }
        
        // Handle DNS flow
        handleDNSFlow(flow, remoteEndpoint: remoteEndpoint)
        return true
    }
    
    /// Extracts the port from an NWEndpoint without using the deprecated NWHostEndpoint.
    @available(iOS, deprecated: 18.0)
    @available(macOS, deprecated: 15.0)
    private func isDNSEndpoint(_ endpoint: NWEndpoint) -> Bool {
        let description = endpoint.description
        // NWEndpoint descriptions are formatted as "host:port"
        guard let lastColon = description.lastIndex(of: ":") else { return false }
        let portString = description[description.index(after: lastColon)...]
        return portString == "53"
    }
    
    // MARK: - DNS Handling
    
    @available(iOS, deprecated: 18.0)
    @available(macOS, deprecated: 15.0)
    @available(tvOS, deprecated: 18.0)
    private func handleDNSFlow(_ flow: NEAppProxyUDPFlow, remoteEndpoint: NWEndpoint) {
        flow.open(withLocalEndpoint: nil) { [weak self] error in
            guard let self = self, error == nil else {
                flow.closeReadWithError(error)
                flow.closeWriteWithError(error)
                return
            }
            
            self.readDNSQueries(flow: flow, remoteEndpoint: remoteEndpoint)
        }
    }
    
    @available(iOS, deprecated: 18.0)
    @available(macOS, deprecated: 15.0)
    @available(tvOS, deprecated: 18.0)
    private func readDNSQueries(flow: NEAppProxyUDPFlow, remoteEndpoint: NWEndpoint) {
        flow.readDatagrams { [weak self] datagrams, endpoints, error in
            guard let self = self else { return }
            
            if let error = error {
                self.log("Error reading DNS datagrams: \(error.localizedDescription)")
                flow.closeReadWithError(error)
                return
            }
            
            guard let datagrams = datagrams, !datagrams.isEmpty else {
                // No more data, continue reading
                self.readDNSQueries(flow: flow, remoteEndpoint: remoteEndpoint)
                return
            }
            
            // Process each DNS query
            for datagram in datagrams {
                self.processDNSQuery(datagram, flow: flow, remoteEndpoint: remoteEndpoint)
            }
            
            // Continue reading
            self.readDNSQueries(flow: flow, remoteEndpoint: remoteEndpoint)
        }
    }
    
    @available(iOS, deprecated: 18.0)
    @available(macOS, deprecated: 15.0)
    private func processDNSQuery(_ query: Data, flow: NEAppProxyUDPFlow, remoteEndpoint: NWEndpoint) {
        statsLock.lock()
        totalQueries += 1
        statsLock.unlock()
        
        // Parse DNS query
        guard let queryInfo = DNSParser.parseQuery(query) else {
            // Can't parse - forward as-is
            forwardDNSQuery(query, flow: flow, remoteEndpoint: remoteEndpoint)
            return
        }
        
        let domain = queryInfo.domain.lowercased()
        
        // Check if domain should be blocked
        if let matcher = domainMatcher, matcher.isBlocked(domain) {
            // Block this domain
            statsLock.lock()
            blockedCount += 1
            statsLock.unlock()
            log("Blocked DNS: \(domain)")
            
            // Send blocked response (0.0.0.0)
            if let blockedResponse = DNSParser.createBlockedResponse(for: query) {
                flow.writeDatagrams([blockedResponse], sentBy: [remoteEndpoint]) { error in
                    if let error = error {
                        NSLog("[ShadowGuard DNS] Error sending blocked response: \(error)")
                    }
                }
            }
            
            // Update stats
            updateBlockedStats(domain: domain)
            return
        }
        
        // Domain not blocked - forward to real DNS
        forwardDNSQuery(query, flow: flow, remoteEndpoint: remoteEndpoint)
    }
    
    @available(iOS, deprecated: 18.0)
    @available(macOS, deprecated: 15.0)
    private func forwardDNSQuery(_ query: Data, flow: NEAppProxyUDPFlow, remoteEndpoint: NWEndpoint) {
        // Forward to upstream DNS server
        // The system will handle the actual forwarding since we're a proxy
        flow.writeDatagrams([query], sentBy: [remoteEndpoint]) { error in
            if let error = error {
                NSLog("[ShadowGuard DNS] Error forwarding query: \(error)")
            }
        }
    }
    
    // MARK: - Blocklist Management
    
    private func loadBlocklists() async {
        domainMatcher = HighPerformanceDomainMatcher(expectedDomains: 500_000)
        
        // Load from app group shared storage
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            log("Failed to access app group container")
            loadBundledBlocklists()
            return
        }
        
        let listsDir = containerURL.appendingPathComponent("FilterLists", isDirectory: true)
        
        // Load each enabled list
        if let userDefaults = UserDefaults(suiteName: appGroup),
           let enabledLists = userDefaults.dictionary(forKey: "filterListStates") as? [String: Bool] {
            
            for (listID, isEnabled) in enabledLists where isEnabled {
                let listFile = listsDir.appendingPathComponent("\(listID).txt")
                if let content = try? String(contentsOf: listFile, encoding: .utf8) {
                    parseAndAddDomains(from: content)
                }
            }
        }
        
        // Load custom rules
        if let userDefaults = UserDefaults(suiteName: appGroup),
           let customRulesData = userDefaults.data(forKey: "customFilterRules"),
           let customRules = try? JSONDecoder().decode([CustomRuleDTO].self, from: customRulesData) {
            
            for rule in customRules where rule.isEnabled && rule.type == "Block" {
                domainMatcher?.addDomain(rule.pattern)
            }
        }
        
        // If no lists loaded, use bundled defaults
        if domainMatcher?.totalDomains == 0 {
            loadBundledBlocklists()
        }
        
        log("Loaded \(domainMatcher?.totalDomains ?? 0) domains into matcher")
    }
    
    private func loadBundledBlocklists() {
        // Bundled minimal blocklist for common ad domains
        let commonAdDomains = [
            "doubleclick.net",
            "googlesyndication.com",
            "googleadservices.com",
            "google-analytics.com",
            "googletagmanager.com",
            "facebook.com/tr",
            "connect.facebook.net",
            "ads.facebook.com",
            "pixel.facebook.com",
            "analytics.twitter.com",
            "ads-twitter.com",
            "ads.yahoo.com",
            "advertising.com",
            "adnxs.com",
            "adsrvr.org",
            "criteo.com",
            "criteo.net",
            "outbrain.com",
            "taboola.com",
            "amazon-adsystem.com",
            "moatads.com",
            "scorecardresearch.com",
            "quantserve.com",
            "pubmatic.com",
            "rubiconproject.com",
            "openx.net",
            "casalemedia.com",
            "indexww.com",
            "bidswitch.net",
            "smartadserver.com",
            "adform.net",
            "adsafeprotected.com",
            "doubleverify.com",
            "serving-sys.com",
            "flashtalking.com",
            "sizmek.com",
            "2mdn.net",
            "admob.com",
            "appsflyer.com",
            "adjust.com",
            "branch.io",
            "app.link",
            "mopub.com",
            "unity3d.com/ads",
            "unityads.unity3d.com",
            "chartboost.com",
            "vungle.com",
            "ironsrc.com",
            "applovin.com",
            "inmobi.com",
            "adcolony.com"
        ]
        
        domainMatcher?.addDomains(commonAdDomains)
    }
    
    private func parseAndAddDomains(from content: String) {
        let lines = content.components(separatedBy: .newlines)
        var domains: [String] = []
        domains.reserveCapacity(lines.count)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("#") || trimmed.hasPrefix("[") {
                continue
            }
            
            // Hosts file format
            if trimmed.hasPrefix("0.0.0.0 ") || trimmed.hasPrefix("127.0.0.1 ") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2 {
                    let domain = String(parts[1])
                    if domain != "localhost" && !domain.hasPrefix("#") {
                        domains.append(domain)
                    }
                }
                continue
            }
            
            // AdBlock domain anchor format
            if trimmed.hasPrefix("||") && trimmed.hasSuffix("^") {
                var domain = trimmed
                domain.removeFirst(2)
                domain.removeLast()
                if !domain.contains("*") && !domain.contains("$") {
                    domains.append(domain)
                }
                continue
            }
            
            // Simple domain format
            if !trimmed.contains("/") && !trimmed.contains("*") && !trimmed.contains("$") &&
               !trimmed.contains("#") && !trimmed.contains("@") && trimmed.contains(".") {
                domains.append(trimmed)
            }
        }
        
        domainMatcher?.addDomains(domains)
    }
    
    // MARK: - Stats
    
    private func updateBlockedStats(domain: String) {
        guard let userDefaults = UserDefaults(suiteName: appGroup) else { return }
        
        // Increment blocked count
        var count = userDefaults.integer(forKey: "blockedCount")
        count += 1
        userDefaults.set(count, forKey: "blockedCount")
        
        // Update blocked domains
        var blockedDomains = userDefaults.dictionary(forKey: "blockedDomains") as? [String: Int] ?? [:]
        blockedDomains[domain] = (blockedDomains[domain] ?? 0) + 1
        userDefaults.set(blockedDomains, forKey: "blockedDomains")
    }
    
    private func saveStats() {
        guard let userDefaults = UserDefaults(suiteName: appGroup) else { return }
        
        userDefaults.set(blockedCount, forKey: "dnsBlockedCount")
        userDefaults.set(totalQueries, forKey: "dnsTotalQueries")
    }
    
    // MARK: - Logging
    
    private func log(_ message: String) {
        NSLog("[ShadowGuard DNS] \(message)")
        
        // Also save to app group for main app
        guard let userDefaults = UserDefaults(suiteName: appGroup) else { return }
        
        var logs = userDefaults.array(forKey: "dnsProxyLogs") as? [[String: Any]] ?? []
        logs.append([
            "timestamp": Date().timeIntervalSince1970,
            "message": message
        ])
        
        // Keep last 500 logs
        if logs.count > 500 {
            logs = Array(logs.suffix(500))
        }
        
        userDefaults.set(logs, forKey: "dnsProxyLogs")
    }
}

// MARK: - DTO for Custom Rules
private struct CustomRuleDTO: Codable {
    let pattern: String
    let type: String
    let isEnabled: Bool
}

// MARK: - Shared Domain Matcher (copied for extension)
// Note: In production, this would be in a shared framework

final class HighPerformanceDomainMatcher: @unchecked Sendable {
    
    private let trie: DomainTrieSimple
    private let lock = NSLock()
    private(set) var totalDomains: Int = 0
    
    init(expectedDomains: Int = 500_000) {
        self.trie = DomainTrieSimple()
    }
    
    func addDomain(_ domain: String, ruleInfo: String? = nil) {
        let normalized = normalizeDomain(domain)
        guard !normalized.isEmpty else { return }
        
        trie.insert(normalized)
        
        lock.lock()
        totalDomains += 1
        lock.unlock()
    }
    
    func addDomains(_ domains: [String]) {
        for domain in domains {
            addDomain(domain)
        }
    }
    
    func isBlocked(_ domain: String) -> Bool {
        let normalized = normalizeDomain(domain)
        return trie.contains(normalized)
    }
    
    private func normalizeDomain(_ domain: String) -> String {
        var d = domain.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if d.hasPrefix("https://") { d = String(d.dropFirst(8)) }
        else if d.hasPrefix("http://") { d = String(d.dropFirst(7)) }
        
        if let slashIndex = d.firstIndex(of: "/") { d = String(d[..<slashIndex]) }
        if let colonIndex = d.firstIndex(of: ":") { d = String(d[..<colonIndex]) }
        
        d = d.replacingOccurrences(of: "||", with: "")
        d = d.replacingOccurrences(of: "^", with: "")
        
        return d
    }
}

final class DomainTrieSimple {
    
    private class Node {
        var children: [String: Node] = [:]
        var isEnd: Bool = false
        var isWildcard: Bool = false
    }
    
    private let root = Node()
    private let lock = NSLock()
    
    func insert(_ domain: String) {
        lock.lock()
        defer { lock.unlock() }
        
        var clean = domain
        var wildcard = false
        
        if clean.hasPrefix("*.") {
            clean = String(clean.dropFirst(2))
            wildcard = true
        }
        
        let labels = clean.split(separator: ".").reversed().map(String.init)
        var current = root
        
        for label in labels {
            if current.children[label] == nil {
                current.children[label] = Node()
            }
            current = current.children[label]!
        }
        
        current.isEnd = true
        current.isWildcard = wildcard
    }
    
    func contains(_ domain: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let labels = domain.lowercased().split(separator: ".").reversed().map(String.init)
        var current = root
        
        for label in labels {
            if current.isWildcard && current.isEnd {
                return true
            }
            
            guard let next = current.children[label] else {
                return false
            }
            current = next
        }
        
        return current.isEnd
    }
}

enum DNSParser {
    struct QueryInfo {
        let domain: String
        let qtype: UInt16
        let qclass: UInt16
        let questionEndOffset: Int
    }

    static func parseQuery(_ data: Data) -> QueryInfo? {
        guard data.count >= 12 else { return nil }

        var offset = 12
        var labels: [String] = []

        while offset < data.count {
            let len = Int(data[offset])
            offset += 1

            if len == 0 { break }
            guard len <= 63, offset + len <= data.count else { return nil }

            let labelData = data.subdata(in: offset..<(offset + len))
            guard let label = String(data: labelData, encoding: .utf8) else { return nil }
            labels.append(label)
            offset += len
        }

        let domain = labels.joined(separator: ".")
        guard !domain.isEmpty else { return nil }
        guard offset + 4 <= data.count else { return nil }

        let qtype = readUInt16(data, offset)
        let qclass = readUInt16(data, offset + 2)
        let questionEndOffset = offset + 4

        return QueryInfo(domain: domain, qtype: qtype, qclass: qclass, questionEndOffset: questionEndOffset)
    }

    static func createBlockedResponse(for query: Data) -> Data? {
        guard let info = parseQuery(query) else { return nil }

        let id = readUInt16(query, 0)
        let requestFlags = readUInt16(query, 2)
        let rd = requestFlags & 0x0100

        let isA = info.qtype == 1
        let isAAAA = info.qtype == 28

        var response = Data()
        response.reserveCapacity(query.count + 64)

        appendUInt16(id, to: &response)

        if !(isA || isAAAA) {
            // NXDOMAIN
            let flags: UInt16 = 0x8000 | rd | 0x0080 | 0x0003
            appendUInt16(flags, to: &response)
            appendUInt16(1, to: &response) // QDCOUNT
            appendUInt16(0, to: &response) // ANCOUNT
            appendUInt16(0, to: &response) // NSCOUNT
            appendUInt16(0, to: &response) // ARCOUNT

            response.append(query.subdata(in: 12..<info.questionEndOffset))
            return response
        }

        let flags: UInt16 = 0x8000 | rd | 0x0080
        appendUInt16(flags, to: &response)
        appendUInt16(1, to: &response) // QDCOUNT
        appendUInt16(1, to: &response) // ANCOUNT
        appendUInt16(0, to: &response) // NSCOUNT
        appendUInt16(0, to: &response) // ARCOUNT

        response.append(query.subdata(in: 12..<info.questionEndOffset))

        // NAME: pointer to question name at 0x000c
        response.append(0xC0)
        response.append(0x0C)

        appendUInt16(info.qtype, to: &response) // TYPE
        appendUInt16(info.qclass, to: &response) // CLASS
        appendUInt32(60, to: &response) // TTL

        if isA {
            appendUInt16(4, to: &response)
            response.append(contentsOf: [0, 0, 0, 0])
        } else {
            appendUInt16(16, to: &response)
            response.append(Data(repeating: 0, count: 16))
        }

        return response
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }
}
