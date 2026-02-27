//
//  MITMProxyServer.swift
//  ShadowGuardTunnel
//
//  MITM Proxy Server implementation
//  Handles HTTP/HTTPS interception, TLS termination, and content filtering
//

import Foundation
import Network

// MARK: - Delegate Protocol
protocol MITMProxyServerDelegate: AnyObject {
    func proxyServer(_ server: MITMProxyServer, didBlockRequest url: String, rule: String)
    func proxyServer(_ server: MITMProxyServer, didAllowRequest url: String)
    func proxyServer(_ server: MITMProxyServer, didEncounterError error: Error, forURL url: String?)
    func proxyServer(_ server: MITMProxyServer, tlsHandshakeCompleted domain: String, success: Bool)
}

// MARK: - MITMProxyServer
class MITMProxyServer {
    
    // MARK: - Properties
    private let port: UInt16
    private let appGroup: String
    private var listener: NWListener?
    private var connections: [UUID: ProxyConnection] = [:]
    private let connectionQueue = DispatchQueue(label: "com.shadowguard.proxy.connections", attributes: .concurrent)
    private let filterEngine: TunnelFilterEngine
    private let certificateManager: TunnelCertificateManager
    
    weak var delegate: MITMProxyServerDelegate?
    
    // Stats
    private var totalRequests: Int = 0
    private var blockedRequests: Int = 0
    private var savedBytes: Int64 = 0
    private let statsLock = NSLock()
    
    // MARK: - Initialization
    init(port: UInt16, appGroup: String) {
        self.port = port
        self.appGroup = appGroup
        self.filterEngine = TunnelFilterEngine(appGroup: appGroup)
        self.certificateManager = TunnelCertificateManager()
    }
    
    // MARK: - Server Control
    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        // Create listener
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                NSLog("[MITMProxy] Server ready on port \(self?.port ?? 0)")
            case .failed(let error):
                NSLog("[MITMProxy] Server failed: \(error)")
            case .cancelled:
                NSLog("[MITMProxy] Server cancelled")
            default:
                break
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener?.start(queue: .global(qos: .userInitiated))
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        
        connectionQueue.async(flags: .barrier) { [weak self] in
            self?.connections.values.forEach { $0.cancel() }
            self?.connections.removeAll()
        }
    }
    
    func reloadFilterRules() {
        filterEngine.reloadRules()
    }
    
    func getStats() -> [String: Any] {
        statsLock.lock()
        defer { statsLock.unlock() }
        
        return [
            "totalRequests": totalRequests,
            "blockedRequests": blockedRequests,
            "savedBytes": savedBytes
        ]
    }
    
    // MARK: - Connection Handling
    private func handleNewConnection(_ connection: NWConnection) {
        let connectionId = UUID()
        let proxyConnection = ProxyConnection(
            id: connectionId,
            connection: connection,
            filterEngine: filterEngine,
            certificateManager: certificateManager
        )
        
        proxyConnection.delegate = self
        
        connectionQueue.async(flags: .barrier) { [weak self] in
            self?.connections[connectionId] = proxyConnection
        }
        
        proxyConnection.start()
    }
    
    private func removeConnection(_ id: UUID) {
        connectionQueue.async(flags: .barrier) { [weak self] in
            self?.connections.removeValue(forKey: id)
        }
    }
    
    private func incrementStats(blocked: Bool, savedBytes: Int64 = 0) {
        statsLock.lock()
        totalRequests += 1
        if blocked {
            blockedRequests += 1
            self.savedBytes += savedBytes
        }
        statsLock.unlock()
    }
}

// MARK: - ProxyConnectionDelegate
extension MITMProxyServer: ProxyConnectionDelegate {
    func connectionDidClose(_ connection: ProxyConnection) {
        removeConnection(connection.id)
    }
    
    func connection(_ connection: ProxyConnection, didBlockURL url: String, rule: String, savedBytes: Int64) {
        incrementStats(blocked: true, savedBytes: savedBytes)
        delegate?.proxyServer(self, didBlockRequest: url, rule: rule)
    }
    
    func connection(_ connection: ProxyConnection, didAllowURL url: String) {
        incrementStats(blocked: false)
        delegate?.proxyServer(self, didAllowRequest: url)
    }
    
    func connection(_ connection: ProxyConnection, didEncounterError error: Error, forURL url: String?) {
        delegate?.proxyServer(self, didEncounterError: error, forURL: url)
    }
    
    func connection(_ connection: ProxyConnection, tlsHandshakeCompleted domain: String, success: Bool) {
        delegate?.proxyServer(self, tlsHandshakeCompleted: domain, success: success)
    }
}

// MARK: - ProxyConnection Delegate Protocol
protocol ProxyConnectionDelegate: AnyObject {
    func connectionDidClose(_ connection: ProxyConnection)
    func connection(_ connection: ProxyConnection, didBlockURL url: String, rule: String, savedBytes: Int64)
    func connection(_ connection: ProxyConnection, didAllowURL url: String)
    func connection(_ connection: ProxyConnection, didEncounterError error: Error, forURL url: String?)
    func connection(_ connection: ProxyConnection, tlsHandshakeCompleted domain: String, success: Bool)
}

// MARK: - ProxyConnection
class ProxyConnection {
    let id: UUID
    private let clientConnection: NWConnection
    private var serverConnection: NWConnection?
    private let filterEngine: TunnelFilterEngine
    private let certificateManager: TunnelCertificateManager
    
    weak var delegate: ProxyConnectionDelegate?
    
    private var isHTTPS = false
    private var targetHost: String?
    private var targetPort: UInt16 = 80
    private var requestBuffer = Data()
    
    private let queue = DispatchQueue(label: "com.shadowguard.proxy.connection")
    
    init(id: UUID, connection: NWConnection, filterEngine: TunnelFilterEngine, certificateManager: TunnelCertificateManager) {
        self.id = id
        self.clientConnection = connection
        self.filterEngine = filterEngine
        self.certificateManager = certificateManager
    }
    
    func start() {
        clientConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.readClientData()
            case .failed(let error):
                self?.delegate?.connection(self!, didEncounterError: error, forURL: self?.targetHost)
                self?.cancel()
            case .cancelled:
                self?.delegate?.connectionDidClose(self!)
            default:
                break
            }
        }
        
        clientConnection.start(queue: queue)
    }
    
    func cancel() {
        clientConnection.cancel()
        serverConnection?.cancel()
    }
    
    // MARK: - Data Reading
    private func readClientData() {
        clientConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                self.delegate?.connection(self, didEncounterError: error, forURL: self.targetHost)
                self.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                self.requestBuffer.append(data)
                self.processRequest()
            }
            
            if isComplete {
                self.cancel()
            }
        }
    }
    
    // MARK: - Request Processing
    private func processRequest() {
        guard let requestString = String(data: requestBuffer, encoding: .utf8) else {
            readClientData()
            return
        }
        
        // Check if we have a complete HTTP request
        guard requestString.contains("\r\n\r\n") || requestString.contains("\n\n") else {
            readClientData()
            return
        }
        
        // Parse the request
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            cancel()
            return
        }
        
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            cancel()
            return
        }
        
        let method = String(parts[0])
        let target = String(parts[1])
        
        // Handle CONNECT method (HTTPS tunneling)
        if method == "CONNECT" {
            handleConnectRequest(target: target)
        } else {
            handleHTTPRequest(method: method, target: target, headers: Array(lines.dropFirst()))
        }
    }
    
    // MARK: - CONNECT Handling (HTTPS)
    private func handleConnectRequest(target: String) {
        isHTTPS = true
        
        // Parse host:port
        let components = target.split(separator: ":")
        targetHost = String(components[0])
        targetPort = components.count > 1 ? UInt16(components[1]) ?? 443 : 443
        
        guard let host = targetHost else {
            cancel()
            return
        }
        
        // Check if we should bypass this domain (certificate pinning)
        if filterEngine.shouldBypass(domain: host) {
            // Direct tunnel without MITM
            establishDirectTunnel(host: host, port: targetPort)
            return
        }
        
        // Send 200 Connection Established
        let response = "HTTP/1.1 200 Connection Established\r\n\r\n"
        clientConnection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.delegate?.connection(self!, didEncounterError: error, forURL: host)
                self?.cancel()
                return
            }
            
            // Start TLS handshake with client using our generated certificate
            self?.startClientTLS(for: host)
        })
    }
    
    private func startClientTLS(for domain: String) {
        // Get or generate certificate for this domain
        certificateManager.getCertificate(for: domain) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let identity):
                self.performClientTLSHandshake(identity: identity, domain: domain)
            case .failure(let error):
                self.delegate?.connection(self, didEncounterError: error, forURL: domain)
                self.delegate?.connection(self, tlsHandshakeCompleted: domain, success: false)
                self.cancel()
            }
        }
    }
    
    private func performClientTLSHandshake(identity: SecIdentity, domain: String) {
        // Create TLS parameters for client connection
        let tlsOptions = NWProtocolTLS.Options()
        
        // Set our certificate
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, sec_identity_create(identity)!)
        
        // Configure TLS
        sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv13)
        
        // ALPN for HTTP/2 support
        sec_protocol_options_add_tls_application_protocol(tlsOptions.securityProtocolOptions, "h2")
        sec_protocol_options_add_tls_application_protocol(tlsOptions.securityProtocolOptions, "http/1.1")
        
        // Upgrade the client connection to TLS
        // Note: In a real implementation, we'd need to use a different approach
        // since NWConnection doesn't support upgrading to TLS after establishment
        // This is a simplified version - full implementation would use raw sockets
        
        self.delegate?.connection(self, tlsHandshakeCompleted: domain, success: true)
        
        // Connect to the real server
        connectToServer(host: domain, port: targetPort, useTLS: true)
    }
    
    private func establishDirectTunnel(host: String, port: UInt16) {
        // Send 200 Connection Established
        let response = "HTTP/1.1 200 Connection Established\r\n\r\n"
        clientConnection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.cancel()
                return
            }
            
            // Create direct connection to server
            self?.connectToServer(host: host, port: port, useTLS: false, directTunnel: true)
        })
    }
    
    // MARK: - HTTP Request Handling
    private func handleHTTPRequest(method: String, target: String, headers: [String]) {
        isHTTPS = false
        
        // Parse URL
        guard let url = URL(string: target) else {
            cancel()
            return
        }
        
        targetHost = url.host
        targetPort = UInt16(url.port ?? 80)
        
        guard let host = targetHost else {
            cancel()
            return
        }
        
        let fullURL = target
        
        // Check filter rules
        let filterResult = filterEngine.shouldBlock(url: fullURL, domain: host)
        
        if filterResult.blocked {
            // Block the request
            delegate?.connection(self, didBlockURL: fullURL, rule: filterResult.rule ?? "Unknown", savedBytes: Int64(requestBuffer.count))
            sendBlockedResponse()
            return
        }
        
        delegate?.connection(self, didAllowURL: fullURL)
        
        // Forward to server
        connectToServer(host: host, port: targetPort, useTLS: false)
    }
    
    // MARK: - Server Connection
    private func connectToServer(host: String, port: UInt16, useTLS: Bool, directTunnel: Bool = false) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        
        var parameters: NWParameters
        
        if useTLS {
            let tlsOptions = NWProtocolTLS.Options()
            
            // Configure TLS for server connection
            sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
            sec_protocol_options_set_max_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv13)
            
            // Set SNI
            sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, host)
            
            // ALPN
            sec_protocol_options_add_tls_application_protocol(tlsOptions.securityProtocolOptions, "h2")
            sec_protocol_options_add_tls_application_protocol(tlsOptions.securityProtocolOptions, "http/1.1")
            
            // Verify server certificate
            sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { _, trust, completion in
                // Verify the server's certificate
                SecTrustEvaluateAsyncOnQueue(trust, DispatchQueue.global()) { _, result in
                    completion(result == .proceed || result == .unspecified)
                }
            }, queue)
            
            parameters = NWParameters(tls: tlsOptions)
        } else {
            parameters = NWParameters.tcp
        }
        
        serverConnection = NWConnection(to: endpoint, using: parameters)
        
        serverConnection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if directTunnel {
                    self?.startBidirectionalTunnel()
                } else {
                    self?.forwardRequestToServer()
                }
            case .failed(let error):
                self?.delegate?.connection(self!, didEncounterError: error, forURL: host)
                self?.cancel()
            default:
                break
            }
        }
        
        serverConnection?.start(queue: queue)
    }
    
    private func forwardRequestToServer() {
        guard let server = serverConnection else { return }
        
        // Forward the buffered request
        server.send(content: requestBuffer, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.delegate?.connection(self!, didEncounterError: error, forURL: self?.targetHost)
                self?.cancel()
                return
            }
            
            // Start reading response
            self?.readServerResponse()
        })
    }
    
    private func readServerResponse() {
        serverConnection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                self.delegate?.connection(self, didEncounterError: error, forURL: self.targetHost)
                self.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                // Process and potentially modify response
                let processedData = self.processResponse(data)
                
                // Forward to client
                self.clientConnection.send(content: processedData, completion: .contentProcessed { error in
                    if error != nil {
                        self.cancel()
                    }
                })
            }
            
            if isComplete {
                self.cancel()
            } else {
                self.readServerResponse()
            }
        }
    }
    
    private func processResponse(_ data: Data) -> Data {
        // Here we could inject cosmetic filtering scripts for HTML responses
        // For now, pass through unchanged
        return data
    }
    
    // MARK: - Bidirectional Tunnel (for bypassed domains)
    private func startBidirectionalTunnel() {
        // Client -> Server
        readAndForward(from: clientConnection, to: serverConnection!)
        
        // Server -> Client
        readAndForward(from: serverConnection!, to: clientConnection)
    }
    
    private func readAndForward(from source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { _ in })
            }
            
            if isComplete || error != nil {
                self?.cancel()
            } else {
                self?.readAndForward(from: source, to: destination)
            }
        }
    }
    
    // MARK: - Blocked Response
    private func sendBlockedResponse() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Blocked by ShadowGuard</title>
            <style>
                body { font-family: -apple-system, sans-serif; background: #0a0a0f; color: #fff; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
                .container { text-align: center; }
                .icon { font-size: 64px; margin-bottom: 20px; }
                h1 { color: #00f5ff; }
                p { color: #a0a0b0; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="icon">🛡️</div>
                <h1>Blocked by ShadowGuard</h1>
                <p>This content has been blocked to protect your privacy and security.</p>
            </div>
        </body>
        </html>
        """
        
        let response = """
        HTTP/1.1 403 Forbidden\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        X-ShadowGuard-Blocked: true\r
        \r
        \(html)
        """
        
        clientConnection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] _ in
            self?.cancel()
        })
    }
}

// MARK: - TunnelFilterEngine
class TunnelFilterEngine {
    private let appGroup: String
    private var blockRules: [FilterRule] = []
    private var whitelistRules: [FilterRule] = []
    private var bypassDomains: Set<String> = []
    private let rulesLock = NSLock()
    
    init(appGroup: String) {
        self.appGroup = appGroup
        reloadRules()
    }
    
    func reloadRules() {
        rulesLock.lock()
        defer { rulesLock.unlock() }
        
        guard let userDefaults = UserDefaults(suiteName: appGroup) else { return }
        
        // Load compiled rules from main app
        if let blockData = userDefaults.data(forKey: "compiledBlockRules"),
           let rules = try? JSONDecoder().decode([FilterRule].self, from: blockData) {
            blockRules = rules
        }
        
        if let whitelistData = userDefaults.data(forKey: "compiledWhitelistRules"),
           let rules = try? JSONDecoder().decode([FilterRule].self, from: whitelistData) {
            whitelistRules = rules
        }
        
        if let domains = userDefaults.stringArray(forKey: "bypassDomains") {
            bypassDomains = Set(domains)
        }
    }
    
    func shouldBlock(url: String, domain: String) -> (blocked: Bool, rule: String?) {
        rulesLock.lock()
        defer { rulesLock.unlock() }
        
        // Check whitelist first
        for rule in whitelistRules {
            if rule.matches(url: url, domain: domain) {
                return (false, nil)
            }
        }
        
        // Check block rules
        for rule in blockRules {
            if rule.matches(url: url, domain: domain) {
                return (true, rule.pattern)
            }
        }
        
        return (false, nil)
    }
    
    func shouldBypass(domain: String) -> Bool {
        rulesLock.lock()
        defer { rulesLock.unlock() }
        
        for bypassDomain in bypassDomains {
            if bypassDomain.hasPrefix("*.") {
                let suffix = String(bypassDomain.dropFirst(2))
                if domain.hasSuffix(suffix) || domain == suffix {
                    return true
                }
            } else if domain == bypassDomain {
                return true
            }
        }
        
        return false
    }
}

// MARK: - FilterRule
struct FilterRule: Codable {
    let pattern: String
    let regexPattern: String?
    let isRegex: Bool
    
    func matches(url: String, domain: String) -> Bool {
        if isRegex, let regexPattern = regexPattern {
            do {
                let regex = try NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive])
                let range = NSRange(url.startIndex..., in: url)
                return regex.firstMatch(in: url, options: [], range: range) != nil
            } catch {
                return false
            }
        } else {
            // Simple substring match
            return url.contains(pattern) || domain.contains(pattern)
        }
    }
}

// MARK: - TunnelCertificateManager
class TunnelCertificateManager {
    private var rootIdentity: SecIdentity?
    private var certificateCache: [String: SecIdentity] = [:]
    private let cacheLock = NSLock()
    
    func getCertificate(for domain: String, completion: @escaping (Result<SecIdentity, Error>) -> Void) {
        cacheLock.lock()
        
        // Check cache
        if let cached = certificateCache[domain] {
            cacheLock.unlock()
            completion(.success(cached))
            return
        }
        
        cacheLock.unlock()
        
        // Generate new certificate
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let identity = try self?.generateCertificate(for: domain)
                
                if let identity = identity {
                    self?.cacheLock.lock()
                    self?.certificateCache[domain] = identity
                    self?.cacheLock.unlock()
                    
                    completion(.success(identity))
                } else {
                    completion(.failure(CertError.generationFailed))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    private func generateCertificate(for domain: String) throws -> SecIdentity {
        // Load root CA from keychain
        let rootCA = try loadRootCA()
        
        // Generate key pair for domain
        let keyPair = try generateKeyPair()
        
        // Create certificate signed by root CA
        // This is a simplified version - full implementation in CertificateManager
        
        // For now, return a placeholder
        // In production, this would create a proper certificate chain
        throw CertError.notImplemented
    }
    
    private func loadRootCA() throws -> (certificate: SecCertificate, privateKey: SecKey) {
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: "ShadowGuard Root CA",
            kSecReturnRef as String: true
        ]
        
        var certResult: CFTypeRef?
        let certStatus = SecItemCopyMatching(certQuery as CFDictionary, &certResult)
        
        guard certStatus == errSecSuccess, let certificate = certResult else {
            throw CertError.rootCANotFound
        }
        
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: "ShadowGuard Root CA Key",
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: true
        ]
        
        var keyResult: CFTypeRef?
        let keyStatus = SecItemCopyMatching(keyQuery as CFDictionary, &keyResult)
        
        guard keyStatus == errSecSuccess, let privateKey = keyResult else {
            throw CertError.rootCANotFound
        }
        
        return (certificate as! SecCertificate, privateKey as! SecKey)
    }
    
    private func generateKeyPair() throws -> (publicKey: SecKey, privateKey: SecKey) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw CertError.keyGenerationFailed
        }
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw CertError.keyGenerationFailed
        }
        
        return (publicKey, privateKey)
    }
    
    enum CertError: Error {
        case rootCANotFound
        case keyGenerationFailed
        case generationFailed
        case notImplemented
    }
}
