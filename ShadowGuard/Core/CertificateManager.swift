//
//  CertificateManager.swift
//  ShadowGuard
//
//  Root CA generation, certificate management, and dynamic cert creation
//  Uses Security framework and CryptoKit for certificate operations
//

import Foundation
import Security
import CryptoKit

actor CertificateManager {
    static let shared = CertificateManager()
    
    // MARK: - Constants
    private let keychainService = "com.shadowguard.certificates"
    private let rootCALabel = "ShadowGuard Root CA"
    private let rootCAKeyLabel = "ShadowGuard Root CA Key"
    private let appGroup = "group.com.shadowguard.app"
    
    // MARK: - Properties
    private var rootCertificate: SecCertificate?
    private var rootPrivateKey: SecKey?
    private var certificateCache: [String: CachedCertificate] = [:]
    private let cacheLimit = 1000
    
    // MARK: - Initialization
    private init() {}
    
    // MARK: - Root CA Management
    func loadOrCreateRootCA() async throws -> (certificate: SecCertificate, privateKey: SecKey) {
        // Try to load existing CA
        if let existing = try? loadRootCAFromKeychain() {
            rootCertificate = existing.certificate
            rootPrivateKey = existing.privateKey
            return existing
        }
        
        // Generate new CA
        let newCA = try await generateRootCA()
        try saveRootCAToKeychain(certificate: newCA.certificate, privateKey: newCA.privateKey)
        
        rootCertificate = newCA.certificate
        rootPrivateKey = newCA.privateKey
        
        return newCA
    }
    
    func getRootCertificateData() async throws -> Data {
        let ca = try await loadOrCreateRootCA()
        return SecCertificateCopyData(ca.certificate) as Data
    }
    
    func getRootCertificatePEM() async throws -> String {
        let derData = try await getRootCertificateData()
        let base64 = derData.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN CERTIFICATE-----\n\(base64)\n-----END CERTIFICATE-----"
    }
    
    func isRootCAInstalled() async -> Bool {
        // Check if our CA is in the keychain
        do {
            _ = try await loadOrCreateRootCA()
            return true
        } catch {
            return false
        }
    }
    
    func deleteRootCA() throws {
        // Delete certificate
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: rootCALabel
        ]
        SecItemDelete(certQuery as CFDictionary)
        
        // Delete private key
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: rootCAKeyLabel
        ]
        SecItemDelete(keyQuery as CFDictionary)
        
        rootCertificate = nil
        rootPrivateKey = nil
        certificateCache.removeAll()
    }
    
    // MARK: - Dynamic Certificate Generation
    func generateCertificate(for domain: String) async throws -> (certificate: SecCertificate, privateKey: SecKey, chain: [SecCertificate]) {
        // Check cache
        if let cached = certificateCache[domain], !cached.isExpired {
            return (cached.certificate, cached.privateKey, [cached.certificate])
        }
        
        // Ensure root CA exists
        let rootCA = try await loadOrCreateRootCA()
        
        // Generate new key pair for the domain
        let keyPair = try generateKeyPair(keySize: 2048)
        
        // Create certificate for domain
        let certificate = try createDomainCertificate(
            domain: domain,
            publicKey: keyPair.publicKey,
            signingKey: rootCA.privateKey,
            issuerCert: rootCA.certificate
        )
        
        // Cache the certificate
        let cached = CachedCertificate(
            certificate: certificate,
            privateKey: keyPair.privateKey,
            createdAt: Date()
        )
        
        // Manage cache size
        if certificateCache.count >= cacheLimit {
            // Remove oldest entries
            let sortedKeys = certificateCache.sorted { $0.value.createdAt < $1.value.createdAt }
            for (key, _) in sortedKeys.prefix(cacheLimit / 4) {
                certificateCache.removeValue(forKey: key)
            }
        }
        
        certificateCache[domain] = cached
        
        return (certificate, keyPair.privateKey, [certificate, rootCA.certificate])
    }
    
    func generateCertificateIdentity(for domain: String) async throws -> SecIdentity {
        let (certificate, privateKey, _) = try await generateCertificate(for: domain)
        
        // Create identity from certificate and private key
        // First, we need to add both to the keychain temporarily
        let tempLabel = "ShadowGuard-\(domain)-\(UUID().uuidString)"
        
        // Add private key
        let keyAddQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecValueRef as String: privateKey,
            kSecAttrLabel as String: tempLabel,
            kSecAttrIsPermanent as String: false
        ]
        
        var keyResult: CFTypeRef?
        let keyStatus = SecItemAdd(keyAddQuery as CFDictionary, &keyResult)
        guard keyStatus == errSecSuccess || keyStatus == errSecDuplicateItem else {
            throw CertificateError.keychainError("Failed to add private key: \(keyStatus)")
        }
        
        // Add certificate
        let certAddQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: tempLabel
        ]
        
        var certResult: CFTypeRef?
        let certStatus = SecItemAdd(certAddQuery as CFDictionary, &certResult)
        guard certStatus == errSecSuccess || certStatus == errSecDuplicateItem else {
            throw CertificateError.keychainError("Failed to add certificate: \(certStatus)")
        }
        
        // Get identity
        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: tempLabel,
            kSecReturnRef as String: true
        ]
        
        var identityResult: CFTypeRef?
        let identityStatus = SecItemCopyMatching(identityQuery as CFDictionary, &identityResult)
        
        // Clean up temporary items
        defer {
            let deleteQuery: [String: Any] = [
                kSecAttrLabel as String: tempLabel
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }
        
        guard identityStatus == errSecSuccess, let identity = identityResult else {
            throw CertificateError.identityCreationFailed
        }
        
        return identity as! SecIdentity
    }
    
    // MARK: - Private Methods
    private func generateRootCA() async throws -> (certificate: SecCertificate, privateKey: SecKey) {
        // Generate RSA key pair
        let keyPair = try generateKeyPair(keySize: 4096)
        
        // Create self-signed root CA certificate
        let certificate = try createRootCACertificate(
            publicKey: keyPair.publicKey,
            privateKey: keyPair.privateKey
        )
        
        return (certificate, keyPair.privateKey)
    }
    
    private func generateKeyPair(keySize: Int) throws -> (publicKey: SecKey, privateKey: SecKey) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: keySize,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw CertificateError.keyGenerationFailed(error?.takeRetainedValue().localizedDescription ?? "Unknown error")
        }
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw CertificateError.keyGenerationFailed("Failed to extract public key")
        }
        
        return (publicKey, privateKey)
    }
    
    private func createRootCACertificate(publicKey: SecKey, privateKey: SecKey) throws -> SecCertificate {
        // Build X.509 certificate using ASN.1 DER encoding
        var certData = Data()
        
        // TBSCertificate
        var tbsCert = Data()
        
        // Version (v3 = 2)
        tbsCert.append(contentsOf: ASN1.contextTag(0, content: ASN1.integer(2)))
        
        // Serial number (random)
        var serialBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, serialBytes.count, &serialBytes)
        serialBytes[0] &= 0x7F // Ensure positive
        tbsCert.append(contentsOf: ASN1.integer(Data(serialBytes)))
        
        // Signature algorithm (SHA256 with RSA)
        tbsCert.append(contentsOf: ASN1.sha256WithRSAEncryption())
        
        // Issuer (same as subject for self-signed)
        let issuerName = createDistinguishedName(
            commonName: "ShadowGuard Root CA",
            organization: "ShadowGuard",
            country: "US"
        )
        tbsCert.append(contentsOf: issuerName)
        
        // Validity (10 years)
        let notBefore = Date()
        let notAfter = Calendar.current.date(byAdding: .year, value: 10, to: notBefore)!
        tbsCert.append(contentsOf: ASN1.validity(notBefore: notBefore, notAfter: notAfter))
        
        // Subject (same as issuer)
        tbsCert.append(contentsOf: issuerName)
        
        // Subject Public Key Info
        tbsCert.append(contentsOf: try ASN1.subjectPublicKeyInfo(publicKey: publicKey))
        
        // Extensions (v3)
        var extensions = Data()
        
        // Basic Constraints (CA:TRUE)
        extensions.append(contentsOf: ASN1.basicConstraintsCA(critical: true))
        
        // Key Usage (keyCertSign, cRLSign)
        extensions.append(contentsOf: ASN1.keyUsageCA(critical: true))
        
        // Subject Key Identifier
        extensions.append(contentsOf: try ASN1.subjectKeyIdentifier(publicKey: publicKey))
        
        tbsCert.append(contentsOf: ASN1.contextTag(3, content: ASN1.sequence(extensions)))
        
        // Wrap TBSCertificate
        let tbsCertSequence = ASN1.sequence(tbsCert)
        
        // Sign TBSCertificate
        let signature = try signData(Data(tbsCertSequence), with: privateKey)
        
        // Build final certificate
        certData.append(contentsOf: tbsCertSequence)
        certData.append(contentsOf: ASN1.sha256WithRSAEncryption())
        certData.append(contentsOf: ASN1.bitString(signature))
        
        let finalCert = ASN1.sequence(certData)
        
        guard let certificate = SecCertificateCreateWithData(nil, Data(finalCert) as CFData) else {
            throw CertificateError.certificateCreationFailed
        }
        
        return certificate
    }
    
    private func createDomainCertificate(domain: String, publicKey: SecKey, signingKey: SecKey, issuerCert: SecCertificate) throws -> SecCertificate {
        var certData = Data()
        var tbsCert = Data()
        
        // Version (v3)
        tbsCert.append(contentsOf: ASN1.contextTag(0, content: ASN1.integer(2)))
        
        // Serial number
        var serialBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, serialBytes.count, &serialBytes)
        serialBytes[0] &= 0x7F
        tbsCert.append(contentsOf: ASN1.integer(Data(serialBytes)))
        
        // Signature algorithm
        tbsCert.append(contentsOf: ASN1.sha256WithRSAEncryption())
        
        // Issuer (from CA cert)
        let issuerName = createDistinguishedName(
            commonName: "ShadowGuard Root CA",
            organization: "ShadowGuard",
            country: "US"
        )
        tbsCert.append(contentsOf: issuerName)
        
        // Validity (1 year)
        let notBefore = Date()
        let notAfter = Calendar.current.date(byAdding: .year, value: 1, to: notBefore)!
        tbsCert.append(contentsOf: ASN1.validity(notBefore: notBefore, notAfter: notAfter))
        
        // Subject
        let subjectName = createDistinguishedName(
            commonName: domain,
            organization: "ShadowGuard Generated",
            country: "US"
        )
        tbsCert.append(contentsOf: subjectName)
        
        // Subject Public Key Info
        tbsCert.append(contentsOf: try ASN1.subjectPublicKeyInfo(publicKey: publicKey))
        
        // Extensions
        var extensions = Data()
        
        // Basic Constraints (CA:FALSE)
        extensions.append(contentsOf: ASN1.basicConstraintsEndEntity(critical: true))
        
        // Key Usage (digitalSignature, keyEncipherment)
        extensions.append(contentsOf: ASN1.keyUsageEndEntity(critical: true))
        
        // Extended Key Usage (serverAuth)
        extensions.append(contentsOf: ASN1.extendedKeyUsageServerAuth())
        
        // Subject Alternative Name
        extensions.append(contentsOf: ASN1.subjectAltName(dnsNames: [domain, "*." + domain]))
        
        tbsCert.append(contentsOf: ASN1.contextTag(3, content: ASN1.sequence(extensions)))
        
        let tbsCertSequence = ASN1.sequence(tbsCert)
        
        // Sign with CA private key
        let signature = try signData(Data(tbsCertSequence), with: signingKey)
        
        certData.append(contentsOf: tbsCertSequence)
        certData.append(contentsOf: ASN1.sha256WithRSAEncryption())
        certData.append(contentsOf: ASN1.bitString(signature))
        
        let finalCert = ASN1.sequence(certData)
        
        guard let certificate = SecCertificateCreateWithData(nil, Data(finalCert) as CFData) else {
            throw CertificateError.certificateCreationFailed
        }
        
        return certificate
    }
    
    private func createDistinguishedName(commonName: String, organization: String, country: String) -> [UInt8] {
        var rdnSequence = Data()
        
        // Country
        rdnSequence.append(contentsOf: ASN1.rdnSet(oid: ASN1.OID.countryName, value: country, tag: 0x13)) // PrintableString
        
        // Organization
        rdnSequence.append(contentsOf: ASN1.rdnSet(oid: ASN1.OID.organizationName, value: organization, tag: 0x0C)) // UTF8String
        
        // Common Name
        rdnSequence.append(contentsOf: ASN1.rdnSet(oid: ASN1.OID.commonName, value: commonName, tag: 0x0C)) // UTF8String
        
        return ASN1.sequence(rdnSequence)
    }
    
    private func signData(_ data: Data, with privateKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) else {
            throw CertificateError.signingFailed(error?.takeRetainedValue().localizedDescription ?? "Unknown error")
        }
        
        return signature as Data
    }
    
    // MARK: - Keychain Operations
    private func loadRootCAFromKeychain() throws -> (certificate: SecCertificate, privateKey: SecKey) {
        // Load certificate
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: rootCALabel,
            kSecReturnRef as String: true
        ]
        
        var certResult: CFTypeRef?
        let certStatus = SecItemCopyMatching(certQuery as CFDictionary, &certResult)
        
        guard certStatus == errSecSuccess, let certificate = certResult else {
            throw CertificateError.notFound
        }
        
        // Load private key
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: rootCAKeyLabel,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: true
        ]
        
        var keyResult: CFTypeRef?
        let keyStatus = SecItemCopyMatching(keyQuery as CFDictionary, &keyResult)
        
        guard keyStatus == errSecSuccess, let privateKey = keyResult else {
            throw CertificateError.notFound
        }
        
        return (certificate as! SecCertificate, privateKey as! SecKey)
    }
    
    private func saveRootCAToKeychain(certificate: SecCertificate, privateKey: SecKey) throws {
        // Save certificate
        let certAddQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: rootCALabel,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let certStatus = SecItemAdd(certAddQuery as CFDictionary, nil)
        guard certStatus == errSecSuccess || certStatus == errSecDuplicateItem else {
            throw CertificateError.keychainError("Failed to save certificate: \(certStatus)")
        }
        
        // Save private key
        let keyAddQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecValueRef as String: privateKey,
            kSecAttrLabel as String: rootCAKeyLabel,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let keyStatus = SecItemAdd(keyAddQuery as CFDictionary, nil)
        guard keyStatus == errSecSuccess || keyStatus == errSecDuplicateItem else {
            throw CertificateError.keychainError("Failed to save private key: \(keyStatus)")
        }
    }
}

// MARK: - Supporting Types
private struct CachedCertificate {
    let certificate: SecCertificate
    let privateKey: SecKey
    let createdAt: Date
    
    var isExpired: Bool {
        // Cache for 24 hours
        Date().timeIntervalSince(createdAt) > 86400
    }
}

enum CertificateError: LocalizedError {
    case keyGenerationFailed(String)
    case certificateCreationFailed
    case signingFailed(String)
    case keychainError(String)
    case notFound
    case identityCreationFailed
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed(let reason):
            return "Key generation failed: \(reason)"
        case .certificateCreationFailed:
            return "Failed to create certificate"
        case .signingFailed(let reason):
            return "Signing failed: \(reason)"
        case .keychainError(let reason):
            return "Keychain error: \(reason)"
        case .notFound:
            return "Certificate not found"
        case .identityCreationFailed:
            return "Failed to create identity"
        case .invalidData:
            return "Invalid certificate data"
        }
    }
}

// MARK: - ASN.1 DER Encoding Helpers
private enum ASN1 {
    enum OID {
        static let commonName: [UInt8] = [0x55, 0x04, 0x03]
        static let countryName: [UInt8] = [0x55, 0x04, 0x06]
        static let organizationName: [UInt8] = [0x55, 0x04, 0x0A]
        static let sha256WithRSA: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]
        static let rsaEncryption: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
        static let basicConstraints: [UInt8] = [0x55, 0x1D, 0x13]
        static let keyUsage: [UInt8] = [0x55, 0x1D, 0x0F]
        static let extKeyUsage: [UInt8] = [0x55, 0x1D, 0x25]
        static let subjectKeyIdentifier: [UInt8] = [0x55, 0x1D, 0x0E]
        static let subjectAltName: [UInt8] = [0x55, 0x1D, 0x11]
        static let serverAuth: [UInt8] = [0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01]
    }
    
    static func length(_ length: Int) -> [UInt8] {
        if length < 128 {
            return [UInt8(length)]
        } else if length < 256 {
            return [0x81, UInt8(length)]
        } else if length < 65536 {
            return [0x82, UInt8(length >> 8), UInt8(length & 0xFF)]
        } else {
            return [0x83, UInt8(length >> 16), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
        }
    }
    
    static func sequence(_ content: Data) -> [UInt8] {
        var result: [UInt8] = [0x30]
        result.append(contentsOf: length(content.count))
        result.append(contentsOf: content)
        return result
    }
    
    static func set(_ content: Data) -> [UInt8] {
        var result: [UInt8] = [0x31]
        result.append(contentsOf: length(content.count))
        result.append(contentsOf: content)
        return result
    }
    
    static func integer(_ value: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        var v = value
        
        if v == 0 {
            bytes = [0x00]
        } else {
            while v > 0 {
                bytes.insert(UInt8(v & 0xFF), at: 0)
                v >>= 8
            }
            if bytes[0] & 0x80 != 0 {
                bytes.insert(0x00, at: 0)
            }
        }
        
        var result: [UInt8] = [0x02]
        result.append(contentsOf: length(bytes.count))
        result.append(contentsOf: bytes)
        return result
    }
    
    static func integer(_ data: Data) -> [UInt8] {
        var bytes = Array(data)
        if bytes.first ?? 0 & 0x80 != 0 {
            bytes.insert(0x00, at: 0)
        }
        
        var result: [UInt8] = [0x02]
        result.append(contentsOf: length(bytes.count))
        result.append(contentsOf: bytes)
        return result
    }
    
    static func bitString(_ data: Data) -> [UInt8] {
        var result: [UInt8] = [0x03]
        result.append(contentsOf: length(data.count + 1))
        result.append(0x00) // unused bits
        result.append(contentsOf: data)
        return result
    }
    
    static func octetString(_ data: Data) -> [UInt8] {
        var result: [UInt8] = [0x04]
        result.append(contentsOf: length(data.count))
        result.append(contentsOf: data)
        return result
    }
    
    static func oid(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = [0x06]
        result.append(contentsOf: length(bytes.count))
        result.append(contentsOf: bytes)
        return result
    }
    
    static func utf8String(_ string: String) -> [UInt8] {
        let data = string.data(using: .utf8)!
        var result: [UInt8] = [0x0C]
        result.append(contentsOf: length(data.count))
        result.append(contentsOf: data)
        return result
    }
    
    static func printableString(_ string: String) -> [UInt8] {
        let data = string.data(using: .ascii)!
        var result: [UInt8] = [0x13]
        result.append(contentsOf: length(data.count))
        result.append(contentsOf: data)
        return result
    }
    
    static func utcTime(_ date: Date) -> [UInt8] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dateString = formatter.string(from: date)
        let data = dateString.data(using: .ascii)!
        
        var result: [UInt8] = [0x17]
        result.append(contentsOf: length(data.count))
        result.append(contentsOf: data)
        return result
    }
    
    static func contextTag(_ tag: Int, content: [UInt8]) -> [UInt8] {
        var result: [UInt8] = [UInt8(0xA0 + tag)]
        result.append(contentsOf: length(content.count))
        result.append(contentsOf: content)
        return result
    }
    
    static func null() -> [UInt8] {
        return [0x05, 0x00]
    }
    
    static func sha256WithRSAEncryption() -> [UInt8] {
        var content = Data()
        content.append(contentsOf: oid(OID.sha256WithRSA))
        content.append(contentsOf: null())
        return sequence(content)
    }
    
    static func validity(notBefore: Date, notAfter: Date) -> [UInt8] {
        var content = Data()
        content.append(contentsOf: utcTime(notBefore))
        content.append(contentsOf: utcTime(notAfter))
        return sequence(content)
    }
    
    static func rdnSet(oid: [UInt8], value: String, tag: UInt8) -> [UInt8] {
        var atv = Data()
        atv.append(contentsOf: self.oid(oid))
        
        let valueData = value.data(using: .utf8)!
        var valueBytes: [UInt8] = [tag]
        valueBytes.append(contentsOf: length(valueData.count))
        valueBytes.append(contentsOf: valueData)
        atv.append(contentsOf: valueBytes)
        
        let atvSequence = sequence(atv)
        return set(Data(atvSequence))
    }
    
    static func subjectPublicKeyInfo(publicKey: SecKey) throws -> [UInt8] {
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw CertificateError.invalidData
        }
        
        // RSA public key algorithm identifier
        var algorithmId = Data()
        algorithmId.append(contentsOf: oid(OID.rsaEncryption))
        algorithmId.append(contentsOf: null())
        
        var content = Data()
        content.append(contentsOf: sequence(algorithmId))
        content.append(contentsOf: bitString(keyData))
        
        return sequence(content)
    }
    
    static func basicConstraintsCA(critical: Bool) -> [UInt8] {
        var extValue = Data()
        extValue.append(contentsOf: sequence(Data([0x01, 0x01, 0xFF]))) // CA:TRUE
        
        return extensionSequence(oid: OID.basicConstraints, critical: critical, value: Data(extValue))
    }
    
    static func basicConstraintsEndEntity(critical: Bool) -> [UInt8] {
        let extValue = sequence(Data()) // Empty sequence = CA:FALSE
        return extensionSequence(oid: OID.basicConstraints, critical: critical, value: Data(extValue))
    }
    
    static func keyUsageCA(critical: Bool) -> [UInt8] {
        // keyCertSign (5) + cRLSign (6) = 0x06
        let usage: [UInt8] = [0x03, 0x02, 0x01, 0x06]
        return extensionSequence(oid: OID.keyUsage, critical: critical, value: Data(usage))
    }
    
    static func keyUsageEndEntity(critical: Bool) -> [UInt8] {
        // digitalSignature (0) + keyEncipherment (2) = 0xA0
        let usage: [UInt8] = [0x03, 0x02, 0x05, 0xA0]
        return extensionSequence(oid: OID.keyUsage, critical: critical, value: Data(usage))
    }
    
    static func extendedKeyUsageServerAuth() -> [UInt8] {
        var content = Data()
        content.append(contentsOf: oid(OID.serverAuth))
        let extValue = sequence(content)
        return extensionSequence(oid: OID.extKeyUsage, critical: false, value: Data(extValue))
    }
    
    static func subjectKeyIdentifier(publicKey: SecKey) throws -> [UInt8] {
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw CertificateError.invalidData
        }
        
        // SHA-1 hash of public key
        let hash = Insecure.SHA1.hash(data: keyData)
        let hashData = Data(hash)
        
        let extValue = octetString(hashData)
        return extensionSequence(oid: OID.subjectKeyIdentifier, critical: false, value: Data(extValue))
    }
    
    static func subjectAltName(dnsNames: [String]) -> [UInt8] {
        var content = Data()
        
        for name in dnsNames {
            let nameData = name.data(using: .utf8)!
            var dnsName: [UInt8] = [0x82] // Context tag 2 for dNSName
            dnsName.append(contentsOf: length(nameData.count))
            dnsName.append(contentsOf: nameData)
            content.append(contentsOf: dnsName)
        }
        
        let extValue = sequence(content)
        return extensionSequence(oid: OID.subjectAltName, critical: false, value: Data(extValue))
    }
    
    private static func extensionSequence(oid: [UInt8], critical: Bool, value: Data) -> [UInt8] {
        var content = Data()
        content.append(contentsOf: self.oid(oid))
        
        if critical {
            content.append(contentsOf: [0x01, 0x01, 0xFF]) // BOOLEAN TRUE
        }
        
        content.append(contentsOf: octetString(value))
        
        return sequence(content)
    }
}
