//
//  LogStore.swift
//  ShadowGuard
//
//  Real-time logging system for traffic and events
//

import Foundation
import Combine

@MainActor
final class LogStore: ObservableObject {
    static let shared = LogStore()
    
    // MARK: - Published Properties
    @Published var logs: [LogEntry] = []
    @Published var filteredLogs: [LogEntry] = []
    @Published var searchText: String = ""
    @Published var selectedTypes: Set<LogEntry.LogType> = Set(LogEntry.LogType.allCases)
    
    // MARK: - Properties
    private let maxLogs = 5000
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupFiltering()
    }
    
    // MARK: - Methods
    func addLog(_ type: LogEntry.LogType, _ message: String, domain: String? = nil, url: String? = nil) {
        let entry = LogEntry(
            type: type,
            message: message,
            domain: domain,
            url: url
        )
        
        logs.insert(entry, at: 0)
        
        // Trim old logs
        if logs.count > maxLogs {
            logs = Array(logs.prefix(maxLogs))
        }
        
        applyFilters()
    }
    
    func addBlockedLog(domain: String, url: String, rule: String) {
        addLog(.blocked, "Blocked: \(rule)", domain: domain, url: url)
    }
    
    func addAllowedLog(domain: String, url: String) {
        addLog(.allowed, "Allowed", domain: domain, url: url)
    }
    
    func addTLSLog(domain: String, success: Bool, details: String? = nil) {
        let message = success ? "TLS Handshake OK" : "TLS Handshake Failed: \(details ?? "Unknown")"
        addLog(.tls, message, domain: domain)
    }
    
    func addErrorLog(_ message: String, domain: String? = nil) {
        addLog(.error, message, domain: domain)
    }
    
    func clearLogs() {
        logs.removeAll()
        filteredLogs.removeAll()
    }
    
    func exportLogs() -> String {
        let dateFormatter = ISO8601DateFormatter()
        return logs.map { entry in
            let timestamp = dateFormatter.string(from: entry.timestamp)
            let domain = entry.domain ?? "-"
            return "[\(timestamp)] [\(entry.type.rawValue.uppercased())] [\(domain)] \(entry.message)"
        }.joined(separator: "\n")
    }
    
    // MARK: - Private Methods
    private func setupFiltering() {
        $searchText
            .combineLatest($selectedTypes)
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.applyFilters()
            }
            .store(in: &cancellables)
    }
    
    private func applyFilters() {
        var result = logs
        
        // Filter by type
        result = result.filter { selectedTypes.contains($0.type) }
        
        // Filter by search text
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            result = result.filter { entry in
                entry.message.lowercased().contains(lowercasedSearch) ||
                (entry.domain?.lowercased().contains(lowercasedSearch) ?? false) ||
                (entry.url?.lowercased().contains(lowercasedSearch) ?? false)
            }
        }
        
        filteredLogs = result
    }
}

// MARK: - Log Entry
struct LogEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let type: LogType
    let message: String
    let domain: String?
    let url: String?
    
    init(type: LogType, message: String, domain: String? = nil, url: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.message = message
        self.domain = domain
        self.url = url
    }
    
    enum LogType: String, CaseIterable, Identifiable {
        case blocked = "blocked"
        case allowed = "allowed"
        case tls = "tls"
        case error = "error"
        case warning = "warning"
        case info = "info"
        
        var id: String { rawValue }
        
        var color: String {
            switch self {
            case .blocked: return "neonPink"
            case .allowed: return "neonGreen"
            case .tls: return "neonCyan"
            case .error: return "neonRed"
            case .warning: return "neonOrange"
            case .info: return "neonBlue"
            }
        }
        
        var icon: String {
            switch self {
            case .blocked: return "xmark.shield.fill"
            case .allowed: return "checkmark.shield.fill"
            case .tls: return "lock.fill"
            case .error: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
}
