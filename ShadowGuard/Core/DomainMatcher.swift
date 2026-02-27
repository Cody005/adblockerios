//
//  DomainMatcher.swift
//  ShadowGuard
//
//  High-performance domain matching using Trie and Bloom Filter
//  Optimized for minimal CPU/memory usage and battery efficiency
//

import Foundation

// MARK: - Trie-based Domain Matcher
/// Efficient domain matching using a reversed-label Trie structure
/// Domains are stored reversed (com.google.ads -> ads.google.com) for suffix matching
final class DomainTrie: @unchecked Sendable {
    
    private class TrieNode {
        var children: [String: TrieNode] = [:]
        var isEndOfDomain: Bool = false
        var isWildcard: Bool = false // Matches all subdomains
        var ruleInfo: String? // Original rule for debugging
    }
    
    private let root = TrieNode()
    private let lock = NSLock()
    private(set) var domainCount: Int = 0
    
    // MARK: - Insert
    
    /// Insert a domain into the Trie
    /// - Parameters:
    ///   - domain: Domain to block (e.g., "ads.google.com" or "*.doubleclick.net")
    ///   - ruleInfo: Optional rule information for debugging
    func insert(_ domain: String, ruleInfo: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        
        var cleanDomain = domain.lowercased()
        var isWildcard = false
        
        // Handle wildcard prefix
        if cleanDomain.hasPrefix("*.") {
            cleanDomain = String(cleanDomain.dropFirst(2))
            isWildcard = true
        } else if cleanDomain.hasPrefix("||") {
            cleanDomain = String(cleanDomain.dropFirst(2))
            isWildcard = true
        }
        
        // Remove trailing separators
        cleanDomain = cleanDomain.trimmingCharacters(in: CharacterSet(charactersIn: "^/"))
        
        guard !cleanDomain.isEmpty else { return }
        
        // Split and reverse labels for suffix matching
        let labels = cleanDomain.split(separator: ".").reversed().map(String.init)
        
        var current = root
        for label in labels {
            if current.children[label] == nil {
                current.children[label] = TrieNode()
            }
            current = current.children[label]!
        }
        
        current.isEndOfDomain = true
        current.isWildcard = isWildcard
        current.ruleInfo = ruleInfo
        domainCount += 1
    }
    
    /// Bulk insert domains from a list
    func insertBulk(_ domains: [String]) {
        for domain in domains {
            insert(domain)
        }
    }
    
    // MARK: - Lookup
    
    /// Check if a domain should be blocked
    /// - Parameter domain: Domain to check (e.g., "tracker.ads.google.com")
    /// - Returns: Tuple of (isBlocked, matchedRule)
    func matches(_ domain: String) -> (blocked: Bool, rule: String?) {
        lock.lock()
        defer { lock.unlock() }
        
        let cleanDomain = domain.lowercased()
        let labels = cleanDomain.split(separator: ".").reversed().map(String.init)
        
        var current = root
        var lastWildcardRule: String? = nil
        
        for (index, label) in labels.enumerated() {
            // Check for wildcard match at current level
            if current.isWildcard && current.isEndOfDomain {
                lastWildcardRule = current.ruleInfo
            }
            
            guard let next = current.children[label] else {
                // No exact match - return wildcard if found
                if let rule = lastWildcardRule {
                    return (true, rule)
                }
                return (false, nil)
            }
            
            current = next
            
            // Check for exact match at end
            if index == labels.count - 1 {
                if current.isEndOfDomain {
                    return (true, current.ruleInfo)
                }
                // Check if we matched a wildcard earlier
                if let rule = lastWildcardRule {
                    return (true, rule)
                }
            }
        }
        
        // Check final node
        if current.isEndOfDomain {
            return (true, current.ruleInfo)
        }
        
        if let rule = lastWildcardRule {
            return (true, rule)
        }
        
        return (false, nil)
    }
    
    /// Quick check without rule info (faster)
    func contains(_ domain: String) -> Bool {
        return matches(domain).blocked
    }
    
    // MARK: - Management
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        root.children.removeAll()
        domainCount = 0
    }
}

// MARK: - Bloom Filter
/// Space-efficient probabilistic data structure for quick negative lookups
/// False positives possible, false negatives impossible
final class BloomFilter: @unchecked Sendable {
    
    private var bitArray: [Bool]
    private let size: Int
    private let hashCount: Int
    private let lock = NSLock()
    
    /// Initialize Bloom Filter
    /// - Parameters:
    ///   - expectedElements: Expected number of elements
    ///   - falsePositiveRate: Desired false positive rate (0.01 = 1%)
    init(expectedElements: Int, falsePositiveRate: Double = 0.01) {
        // Calculate optimal size: m = -n*ln(p) / (ln(2)^2)
        let n = Double(expectedElements)
        let p = falsePositiveRate
        let m = ceil(-n * log(p) / pow(log(2), 2))
        
        // Calculate optimal hash count: k = (m/n) * ln(2)
        let k = ceil((m / n) * log(2))
        
        self.size = Int(m)
        self.hashCount = Int(k)
        self.bitArray = [Bool](repeating: false, count: size)
    }
    
    /// Add an element to the filter
    func insert(_ element: String) {
        lock.lock()
        defer { lock.unlock() }
        
        let hashes = computeHashes(element)
        for hash in hashes {
            bitArray[hash] = true
        }
    }
    
    /// Bulk insert elements
    func insertBulk(_ elements: [String]) {
        lock.lock()
        defer { lock.unlock() }
        
        for element in elements {
            let hashes = computeHashesUnsafe(element)
            for hash in hashes {
                bitArray[hash] = true
            }
        }
    }
    
    /// Check if element might be in the set
    /// - Returns: false = definitely not in set, true = probably in set
    func mightContain(_ element: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let hashes = computeHashesUnsafe(element)
        for hash in hashes {
            if !bitArray[hash] {
                return false
            }
        }
        return true
    }
    
    /// Clear the filter
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        bitArray = [Bool](repeating: false, count: size)
    }
    
    // MARK: - Private
    
    private func computeHashes(_ element: String) -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return computeHashesUnsafe(element)
    }
    
    private func computeHashesUnsafe(_ element: String) -> [Int] {
        let data = element.data(using: .utf8)!
        
        // Use two hash functions to generate k hashes
        // h(i) = h1 + i*h2 (double hashing technique)
        let h1 = fnv1aHash(data)
        let h2 = murmurHash(data)
        
        var hashes: [Int] = []
        hashes.reserveCapacity(hashCount)
        
        for i in 0..<hashCount {
            let combinedHash = h1 &+ (i &* h2)
            let index = abs(combinedHash) % size
            hashes.append(index)
        }
        
        return hashes
    }
    
    /// FNV-1a hash function
    private func fnv1aHash(_ data: Data) -> Int {
        var hash: UInt64 = 14695981039346656037
        let prime: UInt64 = 1099511628211
        
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        
        return Int(truncatingIfNeeded: hash)
    }
    
    /// Simple Murmur-inspired hash
    private func murmurHash(_ data: Data) -> Int {
        var hash: UInt64 = 0
        let c1: UInt64 = 0xcc9e2d51
        let c2: UInt64 = 0x1b873593
        
        for (_, byte) in data.enumerated() {
            var k = UInt64(byte)
            k = k &* c1
            k = (k << 15) | (k >> 49)
            k = k &* c2
            
            hash ^= k
            hash = (hash << 13) | (hash >> 51)
            hash = hash &* 5 &+ 0xe6546b64
        }
        
        hash ^= UInt64(data.count)
        hash ^= hash >> 33
        hash = hash &* 0xff51afd7ed558ccd
        hash ^= hash >> 33
        hash = hash &* 0xc4ceb9fe1a85ec53
        hash ^= hash >> 33
        
        return Int(truncatingIfNeeded: hash)
    }
}

// MARK: - Combined High-Performance Matcher
/// Combines Bloom Filter (fast negative check) with Trie (accurate positive check)
final class HighPerformanceDomainMatcher: @unchecked Sendable {
    
    private let bloomFilter: BloomFilter
    private let trie: DomainTrie
    private let lock = NSLock()
    
    private(set) var totalDomains: Int = 0
    private(set) var bloomFilterHits: Int = 0
    private(set) var trieHits: Int = 0
    
    init(expectedDomains: Int = 500_000) {
        self.bloomFilter = BloomFilter(expectedElements: expectedDomains, falsePositiveRate: 0.001)
        self.trie = DomainTrie()
    }
    
    /// Add a domain to block
    func addDomain(_ domain: String, ruleInfo: String? = nil) {
        let normalized = normalizeDomain(domain)
        guard !normalized.isEmpty else { return }
        
        bloomFilter.insert(normalized)
        trie.insert(normalized, ruleInfo: ruleInfo)
        
        lock.lock()
        totalDomains += 1
        lock.unlock()
    }
    
    /// Bulk add domains (more efficient)
    func addDomains(_ domains: [String]) {
        let normalized = domains.compactMap { d -> String? in
            let n = normalizeDomain(d)
            return n.isEmpty ? nil : n
        }
        
        bloomFilter.insertBulk(normalized)
        trie.insertBulk(normalized)
        
        lock.lock()
        totalDomains += normalized.count
        lock.unlock()
    }
    
    /// Check if domain should be blocked
    /// Uses Bloom filter for fast negative, Trie for accurate positive
    func shouldBlock(_ domain: String) -> (blocked: Bool, rule: String?) {
        let normalized = normalizeDomain(domain)
        
        // Fast path: Bloom filter says definitely not blocked
        if !bloomFilter.mightContain(normalized) {
            lock.lock()
            bloomFilterHits += 1
            lock.unlock()
            return (false, nil)
        }
        
        // Bloom filter says maybe blocked - verify with Trie
        let result = trie.matches(normalized)
        
        lock.lock()
        if result.blocked {
            trieHits += 1
        }
        lock.unlock()
        
        return result
    }
    
    /// Quick check without rule info
    func isBlocked(_ domain: String) -> Bool {
        return shouldBlock(domain).blocked
    }
    
    /// Check domain and all parent domains
    func shouldBlockWithParents(_ domain: String) -> (blocked: Bool, rule: String?) {
        var current = domain.lowercased()
        
        while !current.isEmpty {
            let result = shouldBlock(current)
            if result.blocked {
                return result
            }
            
            // Move to parent domain
            if let dotIndex = current.firstIndex(of: ".") {
                current = String(current[current.index(after: dotIndex)...])
            } else {
                break
            }
        }
        
        return (false, nil)
    }
    
    /// Clear all data
    func clear() {
        bloomFilter.clear()
        trie.clear()
        
        lock.lock()
        totalDomains = 0
        bloomFilterHits = 0
        trieHits = 0
        lock.unlock()
    }
    
    /// Get statistics
    func getStats() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        
        return [
            "totalDomains": totalDomains,
            "bloomFilterHits": bloomFilterHits,
            "trieHits": trieHits,
            "bloomFilterEfficiency": totalDomains > 0 ? Double(bloomFilterHits) / Double(bloomFilterHits + trieHits) : 0
        ]
    }
    
    // MARK: - Private
    
    private func normalizeDomain(_ domain: String) -> String {
        var d = domain.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove protocol
        if d.hasPrefix("https://") {
            d = String(d.dropFirst(8))
        } else if d.hasPrefix("http://") {
            d = String(d.dropFirst(7))
        }
        
        // Remove path
        if let slashIndex = d.firstIndex(of: "/") {
            d = String(d[..<slashIndex])
        }
        
        // Remove port
        if let colonIndex = d.firstIndex(of: ":") {
            d = String(d[..<colonIndex])
        }
        
        // Remove AdBlock syntax
        d = d.replacingOccurrences(of: "||", with: "")
        d = d.replacingOccurrences(of: "^", with: "")
        d = d.replacingOccurrences(of: "*.", with: "")
        
        return d
    }
}

// MARK: - IP Address Matcher
/// Efficient IP address blocking using CIDR notation support
final class IPMatcher: @unchecked Sendable {
    
    private var blockedIPs: Set<String> = []
    private var blockedCIDRs: [(ip: UInt32, mask: UInt32)] = []
    private let lock = NSLock()
    
    /// Add an IP address or CIDR range to block
    func addIP(_ ip: String) {
        lock.lock()
        defer { lock.unlock() }
        
        if ip.contains("/") {
            // CIDR notation
            if let cidr = parseCIDR(ip) {
                blockedCIDRs.append(cidr)
            }
        } else {
            blockedIPs.insert(ip)
        }
    }
    
    /// Check if an IP should be blocked
    func isBlocked(_ ip: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        // Check exact match
        if blockedIPs.contains(ip) {
            return true
        }
        
        // Check CIDR ranges
        guard let ipNum = ipToUInt32(ip) else { return false }
        
        for (cidrIP, mask) in blockedCIDRs {
            if (ipNum & mask) == (cidrIP & mask) {
                return true
            }
        }
        
        return false
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        blockedIPs.removeAll()
        blockedCIDRs.removeAll()
    }
    
    // MARK: - Private
    
    private func parseCIDR(_ cidr: String) -> (ip: UInt32, mask: UInt32)? {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              let ip = ipToUInt32(String(parts[0])),
              let prefixLen = Int(parts[1]),
              prefixLen >= 0 && prefixLen <= 32 else {
            return nil
        }
        
        let mask: UInt32 = prefixLen == 0 ? 0 : ~((1 << (32 - prefixLen)) - 1)
        return (ip, mask)
    }
    
    private func ipToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        
        var result: UInt32 = 0
        for (i, part) in parts.enumerated() {
            guard let octet = UInt32(part), octet <= 255 else { return nil }
            result |= octet << (24 - i * 8)
        }
        
        return result
    }
}
