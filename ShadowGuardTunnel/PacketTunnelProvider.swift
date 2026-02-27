//
//  PacketTunnelProvider.swift
//  ShadowGuardTunnel
//
//  Network Extension PacketTunnelProvider for system-wide ad blocking
//  Uses MITM proxy for HTTPS content filtering + DNS blocking for additional coverage
//

import NetworkExtension
import Foundation

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    // MARK: - Properties
    private var pendingStartCompletion: ((Error?) -> Void)?
    private let proxyPort: UInt16 = 8899
    private let dnsPort: UInt16 = 53
    
    private let appGroup = "group.com.shadowguard.app"
    private var isRunning = false
    
    // MITM Proxy Server for HTTPS content filtering
    private var proxyServer: MITMProxyServer?
    
    // High-performance domain matching (for DNS-level blocking)
    private var domainMatcher: TunnelDomainMatcher?
    
    // Statistics
    private var blockedRequests: Int = 0
    private var totalRequests: Int = 0
    private var savedBytes: Int64 = 0
    
    // Logging
    private func log(_ message: String, level: LogLevel = .info) {
        NSLog("[ShadowGuard] [\(level.rawValue)] \(message)")
        
        // Send to main app via app group
        sendLogToMainApp(message: message, level: level)
    }
    
    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }
    
    // MARK: - Lifecycle
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        log("Starting tunnel with MITM proxy...")
        
        pendingStartCompletion = completionHandler
        
        // Configure tunnel network settings with proxy
        let settings = createTunnelSettings()
        
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                self.log("Failed to set tunnel settings: \(error.localizedDescription)", level: .error)
                completionHandler(error)
                return
            }
            
            self.log("Tunnel settings configured successfully")
            
            // Start MITM proxy server for HTTPS content filtering
            self.startProxyServer()
            
            // Load blocklists for DNS-level blocking
            Task {
                await self.loadBlocklists()
                self.startPacketProcessing()
                self.isRunning = true
                self.log("Tunnel started successfully with MITM proxy on port \(self.proxyPort)")
                completionHandler(nil)
            }
        }
    }
    
    private func startProxyServer() {
        log("Starting MITM proxy server on port \(proxyPort)...")
        
        proxyServer = MITMProxyServer(port: proxyPort, appGroup: appGroup)
        proxyServer?.delegate = self
        
        do {
            try proxyServer?.start()
            log("MITM proxy server started successfully")
        } catch {
            log("Failed to start MITM proxy: \(error.localizedDescription)", level: .error)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log("Stopping tunnel with reason: \(reason.rawValue)")
        
        isRunning = false
        proxyServer?.stop()
        proxyServer = nil
        saveStats()
        
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Handle messages from the main app
        guard let message = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
              let command = message["command"] as? String else {
            completionHandler?(nil)
            return
        }
        
        switch command {
        case "getStats":
            let stats = getStats()
            if let data = try? JSONSerialization.data(withJSONObject: stats) {
                completionHandler?(data)
            } else {
                completionHandler?(nil)
            }
            
        case "reloadRules":
            Task {
                await loadBlocklists()
                completionHandler?(Data())
            }
            
        case "getStatus":
            let status: [String: Any] = [
                "isRunning": isRunning,
                "blockedDomains": domainMatcher?.totalDomains ?? 0
            ]
            if let data = try? JSONSerialization.data(withJSONObject: status) {
                completionHandler?(data)
            } else {
                completionHandler?(nil)
            }
            
        case "pause":
            isRunning = false
            completionHandler?(Data())
            
        case "resume":
            isRunning = true
            completionHandler?(Data())
            
        default:
            completionHandler?(nil)
        }
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        log("Tunnel going to sleep")
        completionHandler()
    }
    
    override func wake() {
        log("Tunnel waking up")
    }
    
    // MARK: - Tunnel Configuration
    private func createTunnelSettings() -> NEPacketTunnelNetworkSettings {
        // Use a fake VPN server address (local tunnel)
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.0.0.1")
        
        // IPv4 Settings
        let ipv4Settings = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.0"])
        
        // Route all traffic through the tunnel for inspection
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        
        // Exclude local network to prevent loops
        ipv4Settings.excludedRoutes = [
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0")
        ]
        
        settings.ipv4Settings = ipv4Settings
        
        // IPv6 Settings
        let ipv6Settings = NEIPv6Settings(addresses: ["fd00::2"], networkPrefixLengths: [64])
        ipv6Settings.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6Settings
        
        // DNS Settings
        let dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
        dnsSettings.matchDomains = [""] // Match all domains
        settings.dnsSettings = dnsSettings
        
        // MITM Proxy Settings - Route HTTP/HTTPS through local proxy
        let proxySettings = NEProxySettings()
        proxySettings.httpEnabled = true
        proxySettings.httpServer = NEProxyServer(address: "127.0.0.1", port: Int(proxyPort))
        proxySettings.httpsEnabled = true
        proxySettings.httpsServer = NEProxyServer(address: "127.0.0.1", port: Int(proxyPort))
        proxySettings.matchDomains = [""] // Match all domains
        
        // Bypass domains that shouldn't go through proxy
        proxySettings.exceptionList = loadBypassDomains()
        
        settings.proxySettings = proxySettings
        
        // MTU - Standard for most networks
        settings.mtu = 1500
        
        return settings
    }
    
    private func loadBypassDomains() -> [String] {
        // Domains that should bypass the MITM proxy (certificate pinning, etc.)
        var bypassDomains = [
            // Apple services (certificate pinning)
            "*.apple.com",
            "*.icloud.com",
            "*.mzstatic.com",
            "*.itunes.apple.com",
            
            // Banking and financial (security)
            "*.bank",
            "*.banking",
            
            // Certificate pinned apps
            "*.googleapis.com",
            
            // Local addresses
            "localhost",
            "*.local"
        ]
        
        // Load user-configured bypass domains
        if let userDefaults = UserDefaults(suiteName: appGroup),
           let userBypass = userDefaults.stringArray(forKey: "bypassDomains") {
            bypassDomains.append(contentsOf: userBypass)
        }
        
        return bypassDomains
    }
    
    private func loadWhitelistDomains() -> Set<String> {
        // Domains that should never be blocked (essential services)
        var domains: Set<String> = [
            "apple.com",
            "icloud.com",
            "mzstatic.com",
            "cdn-apple.com"
        ]
        
        // Load user-configured whitelist from app group
        if let userDefaults = UserDefaults(suiteName: appGroup),
           let userDomains = userDefaults.stringArray(forKey: "whitelistDomains") {
            domains.formUnion(userDomains)
        }
        
        return domains
    }
    
    // MARK: - Blocklist Loading
    private func loadBlocklists() async {
        log("Loading blocklists...")
        
        domainMatcher = TunnelDomainMatcher(expectedDomains: 500_000)
        
        // Load from app group shared storage
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            log("Failed to access app group container", level: .error)
            loadBundledBlocklists()
            return
        }
        
        let listsDir = containerURL.appendingPathComponent("FilterLists", isDirectory: true)
        
        // Load each enabled built-in list
        if let userDefaults = UserDefaults(suiteName: appGroup),
           let enabledLists = userDefaults.dictionary(forKey: "filterListStates") as? [String: Bool] {
            
            for (listID, isEnabled) in enabledLists where isEnabled {
                let listFile = listsDir.appendingPathComponent("\(listID).txt")
                if let content = try? String(contentsOf: listFile, encoding: .utf8) {
                    parseAndAddDomains(from: content)
                    log("Loaded built-in list: \(listID)")
                }
            }
        }
        
        // Load custom blocklist sources (user-added URLs)
        if let userDefaults = UserDefaults(suiteName: appGroup),
           let customSourcesData = userDefaults.data(forKey: "customBlocklistSources") {
            
            // Decode custom sources to get their IDs
            struct CustomSource: Codable {
                let id: String
                let isEnabled: Bool
            }
            
            if let customSources = try? JSONDecoder().decode([CustomSource].self, from: customSourcesData) {
                for source in customSources where source.isEnabled {
                    let listFile = listsDir.appendingPathComponent("\(source.id).txt")
                    if let content = try? String(contentsOf: listFile, encoding: .utf8) {
                        parseAndAddDomains(from: content)
                        log("Loaded custom list: \(source.id)")
                    }
                }
            }
        }
        
        // Load custom rules (individual domain rules)
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
        // Bundled list of common ad/tracker domains
        let commonAdDomains = [
            "doubleclick.net", "googlesyndication.com", "googleadservices.com",
            "google-analytics.com", "googletagmanager.com", "googletagservices.com",
            "pagead2.googlesyndication.com", "adservice.google.com",
            "facebook.com/tr", "connect.facebook.net", "pixel.facebook.com",
            "analytics.twitter.com", "ads-twitter.com", "ads.yahoo.com",
            "advertising.com", "adnxs.com", "adsrvr.org",
            "criteo.com", "criteo.net", "outbrain.com", "taboola.com",
            "amazon-adsystem.com", "moatads.com", "scorecardresearch.com",
            "quantserve.com", "pubmatic.com", "rubiconproject.com",
            "openx.net", "casalemedia.com", "indexww.com",
            "bidswitch.net", "smartadserver.com", "adform.net",
            "serving-sys.com", "flashtalking.com", "2mdn.net",
            "admob.com", "appsflyer.com", "adjust.com", "branch.io",
            "mopub.com", "unityads.unity3d.com", "chartboost.com",
            "vungle.com", "ironsrc.com", "applovin.com", "inmobi.com",
            "adcolony.com", "tapjoy.com", "fyber.com"
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
            
            // Hosts file format (0.0.0.0 domain or 127.0.0.1 domain)
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
            
            // AdBlock domain anchor format (||domain^)
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
    
    // MARK: - Packet Processing (SNI + DNS Inspection)
    private func startPacketProcessing() {
        log("Starting packet processing with SNI inspection")
        
        // Read packets from the tunnel
        readPackets()
    }
    
    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self, self.isRunning else { return }
            
            self.processPackets(packets, protocols: protocols)
            
            // Continue reading
            self.readPackets()
        }
    }
    
    private func processPackets(_ packets: [Data], protocols: [NSNumber]) {
        var allowedPackets: [Data] = []
        var allowedProtocols: [NSNumber] = []
        
        for (index, packet) in packets.enumerated() {
            totalRequests += 1
            
            let proto = protocols[index]
            
            // Check if this packet should be blocked
            if shouldBlockPacket(packet, protocolNumber: proto) {
                blockedRequests += 1
                savedBytes += Int64(packet.count)
                // Drop packet by not adding to allowed list
                continue
            }
            
            allowedPackets.append(packet)
            allowedProtocols.append(proto)
        }
        
        // Write allowed packets back to the tunnel
        if !allowedPackets.isEmpty {
            packetFlow.writePackets(allowedPackets, withProtocols: allowedProtocols)
        }
    }
    
    private func shouldBlockPacket(_ packet: Data, protocolNumber: NSNumber) -> Bool {
        guard let matcher = domainMatcher else { return false }
        
        // Parse IP header to get protocol and ports
        guard packet.count >= 20 else { return false }
        
        let ipVersion = (packet[0] >> 4) & 0x0F
        guard ipVersion == 4 else { return false } // IPv4 only for now
        
        let headerLength = Int(packet[0] & 0x0F) * 4
        let ipProtocol = packet[9]
        
        // TCP = 6, UDP = 17
        guard ipProtocol == 6 || ipProtocol == 17 else { return false }
        guard packet.count >= headerLength + 8 else { return false }
        
        let destPort = UInt16(packet[headerLength + 2]) << 8 | UInt16(packet[headerLength + 3])
        
        // Check DNS queries (UDP port 53)
        if ipProtocol == 17 && destPort == 53 {
            return checkDNSPacket(packet, headerLength: headerLength, matcher: matcher)
        }
        
        // Check HTTPS connections (TCP port 443) for SNI
        if ipProtocol == 6 && destPort == 443 {
            return checkTLSPacket(packet, headerLength: headerLength, matcher: matcher)
        }
        
        // Check HTTP connections (TCP port 80)
        if ipProtocol == 6 && destPort == 80 {
            return checkHTTPPacket(packet, headerLength: headerLength, matcher: matcher)
        }
        
        return false
    }
    
    private func checkDNSPacket(_ packet: Data, headerLength: Int, matcher: TunnelDomainMatcher) -> Bool {
        // UDP header is 8 bytes
        let dnsOffset = headerLength + 8
        guard packet.count > dnsOffset else { return false }
        
        let dnsData = packet.subdata(in: dnsOffset..<packet.count)
        
        guard let queryInfo = TunnelDNSParser.parseQuery(dnsData) else { return false }
        
        let domain = queryInfo.domain.lowercased()
        
        if matcher.isBlocked(domain) {
            log("Blocked DNS: \(domain)")
            updateBlockedStats(domain: domain)
            return true
        }
        
        return false
    }
    
    private func checkTLSPacket(_ packet: Data, headerLength: Int, matcher: TunnelDomainMatcher) -> Bool {
        // TCP header minimum is 20 bytes, but we need to check data offset
        guard packet.count >= headerLength + 20 else { return false }
        
        let tcpDataOffset = Int((packet[headerLength + 12] >> 4) & 0x0F) * 4
        let tlsOffset = headerLength + tcpDataOffset
        
        guard packet.count > tlsOffset else { return false }
        
        let tlsData = packet.subdata(in: tlsOffset..<packet.count)
        
        // Extract SNI from TLS ClientHello
        guard let sni = TunnelSNIExtractor.extractSNI(from: tlsData) else { return false }
        
        let domain = sni.lowercased()
        
        if matcher.isBlocked(domain) {
            log("Blocked TLS (SNI): \(domain)")
            updateBlockedStats(domain: domain)
            return true
        }
        
        return false
    }
    
    private func checkHTTPPacket(_ packet: Data, headerLength: Int, matcher: TunnelDomainMatcher) -> Bool {
        // TCP header
        guard packet.count >= headerLength + 20 else { return false }
        
        let tcpDataOffset = Int((packet[headerLength + 12] >> 4) & 0x0F) * 4
        let httpOffset = headerLength + tcpDataOffset
        
        guard packet.count > httpOffset else { return false }
        
        let httpData = packet.subdata(in: httpOffset..<packet.count)
        
        // Look for Host header
        guard let httpString = String(data: httpData, encoding: .utf8) else { return false }
        
        // Find Host header
        let lines = httpString.components(separatedBy: "\r\n")
        for line in lines {
            if line.lowercased().hasPrefix("host:") {
                let host = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                let domain = host.components(separatedBy: ":").first ?? host
                
                if matcher.isBlocked(domain.lowercased()) {
                    log("Blocked HTTP: \(domain)")
                    updateBlockedStats(domain: domain)
                    return true
                }
                break
            }
        }
        
        return false
    }
    
    // MARK: - Statistics
    private func getStats() -> [String: Any] {
        return [
            "blockedRequests": blockedRequests,
            "totalRequests": totalRequests,
            "savedBytes": savedBytes,
            "blockedDomains": domainMatcher?.totalDomains ?? 0
        ]
    }
    
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
        userDefaults.set(blockedRequests, forKey: "tunnelBlockedRequests")
        userDefaults.set(totalRequests, forKey: "tunnelTotalRequests")
        userDefaults.set(savedBytes, forKey: "tunnelSavedBytes")
    }
    
    // MARK: - IPC with Main App
    private func sendLogToMainApp(message: String, level: LogLevel) {
        guard let userDefaults = UserDefaults(suiteName: appGroup) else { return }
        
        var logs = userDefaults.array(forKey: "tunnelLogs") as? [[String: Any]] ?? []
        
        let logEntry: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "level": level.rawValue,
            "message": message
        ]
        
        logs.append(logEntry)
        
        // Keep only last 1000 logs
        if logs.count > 1000 {
            logs = Array(logs.suffix(1000))
        }
        
        userDefaults.set(logs, forKey: "tunnelLogs")
    }
}

// MARK: - Tunnel Domain Matcher (Trie-based)
final class TunnelDomainMatcher {
    
    private class Node {
        var children: [String: Node] = [:]
        var isEnd: Bool = false
        var isWildcard: Bool = false
    }
    
    private let root = Node()
    private let lock = NSLock()
    private(set) var totalDomains: Int = 0
    
    init(expectedDomains: Int = 500_000) {}
    
    func addDomain(_ domain: String) {
        lock.lock()
        defer { lock.unlock() }
        
        var clean = normalizeDomain(domain)
        var wildcard = false
        
        if clean.hasPrefix("*.") {
            clean = String(clean.dropFirst(2))
            wildcard = true
        }
        
        guard !clean.isEmpty else { return }
        
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
        totalDomains += 1
    }
    
    func addDomains(_ domains: [String]) {
        for domain in domains {
            addDomain(domain)
        }
    }
    
    func isBlocked(_ domain: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let clean = normalizeDomain(domain)
        let labels = clean.split(separator: ".").reversed().map(String.init)
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
    
    private func normalizeDomain(_ domain: String) -> String {
        var d = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        d = d.replacingOccurrences(of: "||", with: "")
        d = d.replacingOccurrences(of: "^", with: "")
        return d
    }
}

// MARK: - Tunnel SNI Extractor
final class TunnelSNIExtractor {
    
    static func extractSNI(from data: Data) -> String? {
        guard data.count >= 5 else { return nil }
        
        // Check TLS handshake record
        guard data[0] == 22 else { return nil } // Handshake
        guard data[1] == 3 else { return nil } // TLS version 3.x
        
        let recordLength = Int(data[3]) << 8 | Int(data[4])
        guard data.count >= 5 + recordLength else { return nil }
        
        let handshakeData = data.subdata(in: 5..<min(5 + recordLength, data.count))
        return parseClientHello(handshakeData)
    }
    
    private static func parseClientHello(_ data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        guard data[0] == 1 else { return nil } // ClientHello
        
        var offset = 4
        
        // Skip version (2) + random (32)
        offset += 34
        guard offset < data.count else { return nil }
        
        // Skip session ID
        let sessionIDLen = Int(data[offset])
        offset += 1 + sessionIDLen
        guard offset + 2 < data.count else { return nil }
        
        // Skip cipher suites
        let cipherLen = Int(data[offset]) << 8 | Int(data[offset + 1])
        offset += 2 + cipherLen
        guard offset + 1 < data.count else { return nil }
        
        // Skip compression
        let compLen = Int(data[offset])
        offset += 1 + compLen
        guard offset + 2 < data.count else { return nil }
        
        // Extensions
        let extLen = Int(data[offset]) << 8 | Int(data[offset + 1])
        offset += 2
        let extEnd = offset + extLen
        
        while offset + 4 <= extEnd && offset + 4 <= data.count {
            let extType = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            let extDataLen = Int(data[offset + 2]) << 8 | Int(data[offset + 3])
            offset += 4
            
            if extType == 0 { // SNI extension
                guard offset + extDataLen <= data.count else { return nil }
                return parseSNI(data.subdata(in: offset..<(offset + extDataLen)))
            }
            
            offset += extDataLen
        }
        
        return nil
    }
    
    private static func parseSNI(_ data: Data) -> String? {
        guard data.count >= 5 else { return nil }
        
        var offset = 2 // Skip list length
        
        while offset + 3 < data.count {
            let nameType = data[offset]
            let nameLen = Int(data[offset + 1]) << 8 | Int(data[offset + 2])
            offset += 3
            
            if nameType == 0 && offset + nameLen <= data.count {
                return String(data: data.subdata(in: offset..<(offset + nameLen)), encoding: .utf8)
            }
            offset += nameLen
        }
        
        return nil
    }
}

// MARK: - Tunnel DNS Parser
final class TunnelDNSParser {
    
    struct QueryInfo {
        let domain: String
    }
    
    static func parseQuery(_ data: Data) -> QueryInfo? {
        guard data.count >= 12 else { return nil }
        
        // Check it's a query (QR bit = 0)
        let flags = UInt16(data[2]) << 8 | UInt16(data[3])
        guard flags & 0x8000 == 0 else { return nil }
        
        var offset = 12
        guard let domain = parseDomainName(data, offset: &offset) else { return nil }
        
        return QueryInfo(domain: domain)
    }
    
    private static func parseDomainName(_ data: Data, offset: inout Int) -> String? {
        var labels: [String] = []
        
        while offset < data.count {
            let length = Int(data[offset])
            
            if length == 0 {
                offset += 1
                break
            }
            
            if length & 0xC0 == 0xC0 {
                // Pointer - skip for simplicity
                offset += 2
                break
            }
            
            offset += 1
            guard offset + length <= data.count else { return nil }
            
            if let label = String(data: data.subdata(in: offset..<(offset + length)), encoding: .utf8) {
                labels.append(label)
            }
            offset += length
        }
        
        return labels.isEmpty ? nil : labels.joined(separator: ".")
    }
}

// MARK: - Custom Rule DTO
private struct CustomRuleDTO: Codable {
    let pattern: String
    let type: String
    let isEnabled: Bool
}

// MARK: - MITMProxyServerDelegate
extension PacketTunnelProvider: MITMProxyServerDelegate {
    func proxyServer(_ server: MITMProxyServer, didBlockRequest url: String, rule: String) {
        blockedRequests += 1
        log("MITM Blocked: \(url) (rule: \(rule))")
        
        // Extract domain from URL for stats
        if let urlObj = URL(string: url), let host = urlObj.host {
            updateBlockedStats(domain: host)
        }
    }
    
    func proxyServer(_ server: MITMProxyServer, didAllowRequest url: String) {
        totalRequests += 1
    }
    
    func proxyServer(_ server: MITMProxyServer, didEncounterError error: Error, forURL url: String?) {
        log("MITM Error: \(error.localizedDescription) for \(url ?? "unknown")", level: .error)
    }
    
    func proxyServer(_ server: MITMProxyServer, tlsHandshakeCompleted domain: String, success: Bool) {
        if success {
            log("TLS handshake completed for \(domain)", level: .debug)
        } else {
            log("TLS handshake failed for \(domain)", level: .warning)
        }
    }
}
