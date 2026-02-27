//
//  SNIExtractor.swift
//  ShadowGuard
//
//  Extracts Server Name Indication (SNI) from TLS ClientHello packets
//  No MITM required - pure packet inspection for domain blocking
//

import Foundation

/// Extracts SNI hostname from TLS ClientHello without decryption
/// This allows blocking HTTPS connections by domain without certificate trust
final class SNIExtractor {
    
    // TLS Record Types
    private enum TLSRecordType: UInt8 {
        case changeCipherSpec = 20
        case alert = 21
        case handshake = 22
        case applicationData = 23
    }
    
    // TLS Handshake Types
    private enum TLSHandshakeType: UInt8 {
        case clientHello = 1
        case serverHello = 2
        case certificate = 11
        case serverKeyExchange = 12
        case certificateRequest = 13
        case serverHelloDone = 14
        case certificateVerify = 15
        case clientKeyExchange = 16
        case finished = 20
    }
    
    // TLS Extension Types
    private enum TLSExtension: UInt16 {
        case serverName = 0
        case supportedVersions = 43
        case alpn = 16
    }
    
    // MARK: - Public API
    
    /// Extract SNI hostname from packet data
    /// - Parameter data: Raw packet data (TCP payload)
    /// - Returns: Hostname if found, nil otherwise
    static func extractSNI(from data: Data) -> String? {
        guard data.count >= 5 else { return nil }
        
        // Check if this is a TLS handshake record
        guard data[0] == TLSRecordType.handshake.rawValue else { return nil }
        
        // TLS version (we support 1.0 - 1.3)
        let majorVersion = data[1]
        let minorVersion = data[2]
        guard majorVersion == 3 && minorVersion >= 1 else { return nil }
        
        // Record length
        let recordLength = Int(data[3]) << 8 | Int(data[4])
        guard data.count >= 5 + recordLength else { return nil }
        
        // Parse handshake message
        let handshakeData = data.subdata(in: 5..<(5 + recordLength))
        return parseClientHello(handshakeData)
    }
    
    /// Check if data looks like a TLS ClientHello
    static func isClientHello(_ data: Data) -> Bool {
        guard data.count >= 6 else { return false }
        
        // TLS record: handshake (22)
        guard data[0] == 22 else { return false }
        
        // TLS version 3.x
        guard data[1] == 3 else { return false }
        
        // Handshake type: ClientHello (1)
        guard data[5] == 1 else { return false }
        
        return true
    }
    
    /// Extract all useful info from ClientHello
    static func parseClientHelloInfo(from data: Data) -> ClientHelloInfo? {
        guard let sni = extractSNI(from: data) else { return nil }
        
        var info = ClientHelloInfo(serverName: sni)
        
        // Try to extract ALPN protocols
        if let alpn = extractALPN(from: data) {
            info.alpnProtocols = alpn
        }
        
        // Try to extract TLS version
        if let version = extractTLSVersion(from: data) {
            info.tlsVersion = version
        }
        
        return info
    }
    
    // MARK: - Private Parsing
    
    private static func parseClientHello(_ data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        
        // Handshake type
        guard data[0] == TLSHandshakeType.clientHello.rawValue else { return nil }
        
        // Handshake length (3 bytes)
        let handshakeLength = Int(data[1]) << 16 | Int(data[2]) << 8 | Int(data[3])
        guard data.count >= 4 + handshakeLength else { return nil }
        
        var offset = 4
        
        // Client version (2 bytes)
        guard offset + 2 <= data.count else { return nil }
        offset += 2
        
        // Random (32 bytes)
        guard offset + 32 <= data.count else { return nil }
        offset += 32
        
        // Session ID
        guard offset + 1 <= data.count else { return nil }
        let sessionIDLength = Int(data[offset])
        offset += 1 + sessionIDLength
        guard offset <= data.count else { return nil }
        
        // Cipher suites
        guard offset + 2 <= data.count else { return nil }
        let cipherSuitesLength = Int(data[offset]) << 8 | Int(data[offset + 1])
        offset += 2 + cipherSuitesLength
        guard offset <= data.count else { return nil }
        
        // Compression methods
        guard offset + 1 <= data.count else { return nil }
        let compressionMethodsLength = Int(data[offset])
        offset += 1 + compressionMethodsLength
        guard offset <= data.count else { return nil }
        
        // Extensions
        guard offset + 2 <= data.count else { return nil }
        let extensionsLength = Int(data[offset]) << 8 | Int(data[offset + 1])
        offset += 2
        
        let extensionsEnd = offset + extensionsLength
        guard extensionsEnd <= data.count else { return nil }
        
        // Parse extensions to find SNI
        while offset + 4 <= extensionsEnd {
            let extensionType = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            let extensionLength = Int(data[offset + 2]) << 8 | Int(data[offset + 3])
            offset += 4
            
            guard offset + extensionLength <= extensionsEnd else { break }
            
            if extensionType == TLSExtension.serverName.rawValue {
                // Parse SNI extension
                return parseSNIExtension(data.subdata(in: offset..<(offset + extensionLength)))
            }
            
            offset += extensionLength
        }
        
        return nil
    }
    
    private static func parseSNIExtension(_ data: Data) -> String? {
        guard data.count >= 2 else { return nil }
        
        // SNI list length
        let listLength = Int(data[0]) << 8 | Int(data[1])
        guard data.count >= 2 + listLength else { return nil }
        
        var offset = 2
        
        while offset + 3 <= 2 + listLength {
            let nameType = data[offset]
            let nameLength = Int(data[offset + 1]) << 8 | Int(data[offset + 2])
            offset += 3
            
            guard offset + nameLength <= data.count else { break }
            
            // Name type 0 = hostname
            if nameType == 0 {
                let nameData = data.subdata(in: offset..<(offset + nameLength))
                return String(data: nameData, encoding: .utf8)
            }
            
            offset += nameLength
        }
        
        return nil
    }
    
    private static func extractALPN(from data: Data) -> [String]? {
        guard data.count >= 5 else { return nil }
        guard data[0] == TLSRecordType.handshake.rawValue else { return nil }
        
        let recordLength = Int(data[3]) << 8 | Int(data[4])
        guard data.count >= 5 + recordLength else { return nil }
        
        let handshakeData = data.subdata(in: 5..<(5 + recordLength))
        return parseALPNFromHandshake(handshakeData)
    }
    
    private static func parseALPNFromHandshake(_ data: Data) -> [String]? {
        // Similar parsing to ClientHello but looking for ALPN extension
        guard data.count >= 4 else { return nil }
        guard data[0] == TLSHandshakeType.clientHello.rawValue else { return nil }
        
        var offset = 4
        
        // Skip to extensions (same as parseClientHello)
        guard offset + 2 <= data.count else { return nil }
        offset += 2 // version
        
        guard offset + 32 <= data.count else { return nil }
        offset += 32 // random
        
        guard offset + 1 <= data.count else { return nil }
        let sessionIDLength = Int(data[offset])
        offset += 1 + sessionIDLength
        
        guard offset + 2 <= data.count else { return nil }
        let cipherSuitesLength = Int(data[offset]) << 8 | Int(data[offset + 1])
        offset += 2 + cipherSuitesLength
        
        guard offset + 1 <= data.count else { return nil }
        let compressionMethodsLength = Int(data[offset])
        offset += 1 + compressionMethodsLength
        
        guard offset + 2 <= data.count else { return nil }
        let extensionsLength = Int(data[offset]) << 8 | Int(data[offset + 1])
        offset += 2
        
        let extensionsEnd = offset + extensionsLength
        
        while offset + 4 <= extensionsEnd {
            let extensionType = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            let extensionLength = Int(data[offset + 2]) << 8 | Int(data[offset + 3])
            offset += 4
            
            guard offset + extensionLength <= extensionsEnd else { break }
            
            if extensionType == TLSExtension.alpn.rawValue {
                return parseALPNExtension(data.subdata(in: offset..<(offset + extensionLength)))
            }
            
            offset += extensionLength
        }
        
        return nil
    }
    
    private static func parseALPNExtension(_ data: Data) -> [String]? {
        guard data.count >= 2 else { return nil }
        
        let listLength = Int(data[0]) << 8 | Int(data[1])
        guard data.count >= 2 + listLength else { return nil }
        
        var protocols: [String] = []
        var offset = 2
        
        while offset < 2 + listLength {
            guard offset < data.count else { break }
            let protoLength = Int(data[offset])
            offset += 1
            
            guard offset + protoLength <= data.count else { break }
            let protoData = data.subdata(in: offset..<(offset + protoLength))
            if let proto = String(data: protoData, encoding: .utf8) {
                protocols.append(proto)
            }
            offset += protoLength
        }
        
        return protocols.isEmpty ? nil : protocols
    }
    
    private static func extractTLSVersion(from data: Data) -> String? {
        guard data.count >= 5 else { return nil }
        
        let majorVersion = data[1]
        let minorVersion = data[2]
        
        switch (majorVersion, minorVersion) {
        case (3, 1): return "TLS 1.0"
        case (3, 2): return "TLS 1.1"
        case (3, 3): return "TLS 1.2"
        case (3, 4): return "TLS 1.3"
        default: return "TLS \(majorVersion).\(minorVersion)"
        }
    }
}

// MARK: - Supporting Types

struct ClientHelloInfo {
    var serverName: String
    var alpnProtocols: [String]?
    var tlsVersion: String?
    var cipherSuites: [UInt16]?
}

// MARK: - DNS Packet Parser

/// Parses DNS query packets to extract queried domain
final class DNSParser {
    
    // DNS Header flags
    private enum DNSFlags {
        static let queryResponse: UInt16 = 0x8000
        static let opcodeMask: UInt16 = 0x7800
        static let recursionDesired: UInt16 = 0x0100
    }
    
    // DNS Record Types
    enum DNSRecordType: UInt16 {
        case a = 1
        case ns = 2
        case cname = 5
        case soa = 6
        case ptr = 12
        case mx = 15
        case txt = 16
        case aaaa = 28
        case srv = 33
        case https = 65
    }
    
    /// Parse DNS query and extract domain name
    static func parseQuery(_ data: Data) -> DNSQueryInfo? {
        guard data.count >= 12 else { return nil }
        
        // Transaction ID
        let transactionID = UInt16(data[0]) << 8 | UInt16(data[1])
        
        // Flags
        let flags = UInt16(data[2]) << 8 | UInt16(data[3])
        
        // Check if this is a query (QR bit = 0)
        guard flags & DNSFlags.queryResponse == 0 else { return nil }
        
        // Question count
        let questionCount = UInt16(data[4]) << 8 | UInt16(data[5])
        guard questionCount >= 1 else { return nil }
        
        // Parse first question
        var offset = 12
        guard let domain = parseDomainName(data, offset: &offset) else { return nil }
        
        // Query type
        guard offset + 4 <= data.count else { return nil }
        let queryType = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        let queryClass = UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3])
        
        return DNSQueryInfo(
            transactionID: transactionID,
            domain: domain,
            queryType: DNSRecordType(rawValue: queryType),
            queryClass: queryClass
        )
    }
    
    /// Create a DNS response that blocks the domain (returns 0.0.0.0)
    static func createBlockedResponse(for query: Data) -> Data? {
        guard parseQuery(query) != nil else { return nil }
        
        var response = Data()
        
        // Transaction ID (same as query)
        response.append(query[0])
        response.append(query[1])
        
        // Flags: Response, No error
        response.append(0x81) // QR=1, Opcode=0, AA=0, TC=0, RD=1
        response.append(0x80) // RA=1, Z=0, RCODE=0
        
        // Question count: 1
        response.append(0x00)
        response.append(0x01)
        
        // Answer count: 1
        response.append(0x00)
        response.append(0x01)
        
        // Authority count: 0
        response.append(0x00)
        response.append(0x00)
        
        // Additional count: 0
        response.append(0x00)
        response.append(0x00)
        
        // Copy question section
        var offset = 12
        while offset < query.count && query[offset] != 0 {
            offset += Int(query[offset]) + 1
        }
        offset += 5 // null byte + type + class
        
        if offset <= query.count {
            response.append(query[12..<offset])
        }
        
        // Answer section
        // Name pointer to question
        response.append(0xC0)
        response.append(0x0C)
        
        // Type A
        response.append(0x00)
        response.append(0x01)
        
        // Class IN
        response.append(0x00)
        response.append(0x01)
        
        // TTL: 300 seconds
        response.append(0x00)
        response.append(0x00)
        response.append(0x01)
        response.append(0x2C)
        
        // Data length: 4 (IPv4)
        response.append(0x00)
        response.append(0x04)
        
        // IP: 0.0.0.0
        response.append(0x00)
        response.append(0x00)
        response.append(0x00)
        response.append(0x00)
        
        return response
    }
    
    /// Create NXDOMAIN response
    static func createNXDomainResponse(for query: Data) -> Data? {
        guard query.count >= 12 else { return nil }
        
        var response = Data()
        
        // Transaction ID
        response.append(query[0])
        response.append(query[1])
        
        // Flags: Response, NXDOMAIN
        response.append(0x81)
        response.append(0x83) // RCODE = 3 (NXDOMAIN)
        
        // Counts
        response.append(0x00)
        response.append(0x01) // Questions
        response.append(0x00)
        response.append(0x00) // Answers
        response.append(0x00)
        response.append(0x00) // Authority
        response.append(0x00)
        response.append(0x00) // Additional
        
        // Copy question
        var offset = 12
        while offset < query.count && query[offset] != 0 {
            offset += Int(query[offset]) + 1
        }
        offset += 5
        
        if offset <= query.count {
            response.append(query[12..<offset])
        }
        
        return response
    }
    
    // MARK: - Private
    
    private static func parseDomainName(_ data: Data, offset: inout Int) -> String? {
        var labels: [String] = []
        var jumped = false
        var jumpOffset = offset
        
        while offset < data.count {
            let length = Int(data[offset])
            
            if length == 0 {
                if !jumped {
                    offset += 1
                }
                break
            }
            
            // Check for pointer (compression)
            if length & 0xC0 == 0xC0 {
                if offset + 1 >= data.count { return nil }
                let pointer = Int(length & 0x3F) << 8 | Int(data[offset + 1])
                
                if !jumped {
                    jumpOffset = offset + 2
                }
                offset = pointer
                jumped = true
                continue
            }
            
            offset += 1
            guard offset + length <= data.count else { return nil }
            
            let labelData = data.subdata(in: offset..<(offset + length))
            if let label = String(data: labelData, encoding: .utf8) {
                labels.append(label)
            }
            
            offset += length
        }
        
        if jumped {
            offset = jumpOffset
        }
        
        return labels.isEmpty ? nil : labels.joined(separator: ".")
    }
}

struct DNSQueryInfo {
    let transactionID: UInt16
    let domain: String
    let queryType: DNSParser.DNSRecordType?
    let queryClass: UInt16
}
