//
//  DebugConsoleView.swift
//  ShadowGuard
//
//  Debug console accessible by shaking the device
//

import SwiftUI

struct DebugConsoleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var tunnelManager: TunnelManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var logStore: LogStore
    
    @State private var debugLogs: [DebugLogEntry] = []
    @State private var commandInput = ""
    @State private var isExecuting = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Console output
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(debugLogs) { log in
                                    debugLogRow(log)
                                        .id(log.id)
                                }
                            }
                            .padding(12)
                        }
                        .onChange(of: debugLogs.count) { _, _ in
                            if let lastLog = debugLogs.last {
                                withAnimation {
                                    proxy.scrollTo(lastLog.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    // Command input
                    HStack(spacing: 8) {
                        Text(">")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.neonGreen)
                        
                        TextField("Enter command...", text: $commandInput)
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .foregroundColor(.neonGreen)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit {
                                executeCommand()
                            }
                        
                        if isExecuting {
                            ProgressView()
                                .tint(.neonGreen)
                        } else {
                            Button(action: executeCommand) {
                                Image(systemName: "return")
                                    .foregroundColor(.neonGreen)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(hex: "1a1a1a"))
                }
            }
            .navigationTitle("Debug Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        debugLogs.removeAll()
                        addSystemLog("Console cleared")
                    }
                    .foregroundColor(.neonOrange)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.neonCyan)
                }
            }
            .onAppear {
                initializeConsole()
            }
        }
    }
    
    private func debugLogRow(_ log: DebugLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(log.timestamp)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(.gray)
            
            Text(log.message)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(log.color)
                .textSelection(.enabled)
        }
    }
    
    private func initializeConsole() {
        addSystemLog("ShadowGuard Debug Console v1.0")
        addSystemLog("Type 'help' for available commands")
        addSystemLog("---")
        addInfoLog("Tunnel Status: \(tunnelManager.statusDescription)")
        addInfoLog("Protection Level: \(Int(appState.protectionLevel * 100))%")
        addInfoLog("Blocked Today: \(appState.blockedToday)")
        addInfoLog("Total Logs: \(logStore.logs.count)")
    }
    
    private func executeCommand() {
        let command = commandInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !command.isEmpty else { return }
        
        addCommandLog(commandInput)
        commandInput = ""
        
        isExecuting = true
        
        Task {
            await processCommand(command)
            await MainActor.run {
                isExecuting = false
            }
        }
    }
    
    private func processCommand(_ command: String) async {
        let parts = command.split(separator: " ")
        let cmd = String(parts.first ?? "")
        let args = parts.dropFirst().map { String($0) }
        
        switch cmd {
        case "help":
            showHelp()
            
        case "status":
            showStatus()
            
        case "stats":
            showStats()
            
        case "tunnel":
            await handleTunnelCommand(args)
            
        case "logs":
            handleLogsCommand(args)
            
        case "ca":
            await handleCACommand(args)
            
        case "rules":
            handleRulesCommand(args)
            
        case "clear":
            await MainActor.run {
                debugLogs.removeAll()
                addSystemLog("Console cleared")
            }
            
        case "export":
            handleExportCommand(args)
            
        case "test":
            handleTestCommand(args)
            
        default:
            addErrorLog("Unknown command: \(cmd). Type 'help' for available commands.")
        }
    }
    
    private func showHelp() {
        let commands = [
            ("help", "Show this help message"),
            ("status", "Show current protection status"),
            ("stats", "Show blocking statistics"),
            ("tunnel start", "Start the VPN tunnel"),
            ("tunnel stop", "Stop the VPN tunnel"),
            ("tunnel restart", "Restart the VPN tunnel"),
            ("logs count", "Show log count"),
            ("logs clear", "Clear all logs"),
            ("logs last [n]", "Show last n logs"),
            ("ca status", "Show CA certificate status"),
            ("ca generate", "Generate new root CA"),
            ("rules count", "Show rule counts"),
            ("rules reload", "Reload filter rules"),
            ("test [url]", "Test URL against filters"),
            ("export logs", "Export logs to clipboard"),
            ("clear", "Clear console")
        ]
        
        addSystemLog("Available commands:")
        for (cmd, desc) in commands {
            addInfoLog("  \(cmd.padding(toLength: 18, withPad: " ", startingAt: 0)) - \(desc)")
        }
    }
    
    private func showStatus() {
        addInfoLog("=== Status ===")
        addInfoLog("Tunnel: \(tunnelManager.statusDescription)")
        addInfoLog("Connected: \(tunnelManager.isConnected ? "Yes" : "No")")
        addInfoLog("CA Installed: \(appState.isCAInstalled ? "Yes" : "No")")
        addInfoLog("CA Trusted: \(appState.isCATrusted ? "Yes" : "No")")
        addInfoLog("Protection Level: \(Int(appState.protectionLevel * 100))%")
    }
    
    private func showStats() {
        addInfoLog("=== Statistics ===")
        addInfoLog("Blocked Today: \(appState.blockedToday)")
        addInfoLog("Total Blocked: \(appState.blockedTotal)")
        addInfoLog("Data Saved: \(formatBytes(appState.savedBandwidth))")
        addInfoLog("Top Domains: \(appState.topBlockedDomains.count)")
        
        if !appState.topBlockedDomains.isEmpty {
            addInfoLog("Top 5 Blocked:")
            for domain in appState.topBlockedDomains.prefix(5) {
                addInfoLog("  \(domain.domain): \(domain.count)")
            }
        }
    }
    
    private func handleTunnelCommand(_ args: [String]) async {
        guard let action = args.first else {
            addErrorLog("Usage: tunnel [start|stop|restart]")
            return
        }
        
        switch action {
        case "start":
            addInfoLog("Starting tunnel...")
            do {
                try await tunnelManager.startTunnel()
                addSuccessLog("Tunnel started successfully")
            } catch {
                addErrorLog("Failed to start tunnel: \(error.localizedDescription)")
            }
            
        case "stop":
            addInfoLog("Stopping tunnel...")
            await MainActor.run {
                tunnelManager.stopTunnel()
            }
            addSuccessLog("Tunnel stopped")
            
        case "restart":
            addInfoLog("Restarting tunnel...")
            await MainActor.run {
                tunnelManager.stopTunnel()
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            do {
                try await tunnelManager.startTunnel()
                addSuccessLog("Tunnel restarted successfully")
            } catch {
                addErrorLog("Failed to restart tunnel: \(error.localizedDescription)")
            }
            
        default:
            addErrorLog("Unknown tunnel action: \(action)")
        }
    }
    
    private func handleLogsCommand(_ args: [String]) {
        guard let action = args.first else {
            addErrorLog("Usage: logs [count|clear|last n]")
            return
        }
        
        switch action {
        case "count":
            addInfoLog("Total logs: \(logStore.logs.count)")
            addInfoLog("Blocked: \(logStore.logs.filter { $0.type == .blocked }.count)")
            addInfoLog("Allowed: \(logStore.logs.filter { $0.type == .allowed }.count)")
            addInfoLog("Errors: \(logStore.logs.filter { $0.type == .error }.count)")
            
        case "clear":
            Task { @MainActor in
                logStore.clearLogs()
            }
            addSuccessLog("Logs cleared")
            
        case "last":
            let count = Int(args.dropFirst().first ?? "5") ?? 5
            let lastLogs = logStore.logs.prefix(count)
            addInfoLog("Last \(count) logs:")
            for log in lastLogs {
                addInfoLog("  [\(log.type.rawValue)] \(log.message)")
            }
            
        default:
            addErrorLog("Unknown logs action: \(action)")
        }
    }
    
    private func handleCACommand(_ args: [String]) async {
        guard let action = args.first else {
            addErrorLog("Usage: ca [status|generate]")
            return
        }
        
        switch action {
        case "status":
            let installed = await CertificateManager.shared.isRootCAInstalled()
            addInfoLog("CA Installed: \(installed ? "Yes" : "No")")
            addInfoLog("CA Trusted: \(appState.isCATrusted ? "Yes" : "No")")
            
        case "generate":
            addInfoLog("Generating new root CA...")
            do {
                _ = try await CertificateManager.shared.loadOrCreateRootCA()
                addSuccessLog("Root CA generated successfully")
            } catch {
                addErrorLog("Failed to generate CA: \(error.localizedDescription)")
            }
            
        default:
            addErrorLog("Unknown CA action: \(action)")
        }
    }
    
    private func handleRulesCommand(_ args: [String]) {
        guard let action = args.first else {
            addErrorLog("Usage: rules [count|reload]")
            return
        }
        
        switch action {
        case "count":
            let engine = FilterEngine.shared
            let enabledLists = engine.builtInLists.filter { $0.isEnabled }.count
            let totalLists = engine.builtInLists.count
            let customRules = engine.customRules.count
            
            addInfoLog("Filter Lists: \(enabledLists)/\(totalLists) enabled")
            addInfoLog("Custom Rules: \(customRules)")
            
        case "reload":
            addInfoLog("Reloading filter rules...")
            Task {
                await FilterEngine.shared.compileAllRules()
                addSuccessLog("Rules reloaded")
            }
            
        default:
            addErrorLog("Unknown rules action: \(action)")
        }
    }
    
    private func handleTestCommand(_ args: [String]) {
        guard let url = args.first else {
            addErrorLog("Usage: test [url]")
            return
        }
        
        let domain = URL(string: url)?.host ?? url
        let result = FilterEngine.shared.shouldBlock(url: url, domain: domain)
        
        if result.isBlocked {
            addWarningLog("URL would be BLOCKED")
            addInfoLog("Reason: \(result.reason)")
        } else {
            addSuccessLog("URL would be ALLOWED")
            addInfoLog("Reason: \(result.reason)")
        }
    }
    
    private func handleExportCommand(_ args: [String]) {
        guard let target = args.first else {
            addErrorLog("Usage: export [logs]")
            return
        }
        
        switch target {
        case "logs":
            let exported = logStore.exportLogs()
            UIPasteboard.general.string = exported
            addSuccessLog("Logs exported to clipboard (\(exported.count) characters)")
            
        default:
            addErrorLog("Unknown export target: \(target)")
        }
    }
    
    // MARK: - Log Helpers
    private func addSystemLog(_ message: String) {
        addLog(message, color: .white)
    }
    
    private func addCommandLog(_ message: String) {
        addLog("> \(message)", color: .neonCyan)
    }
    
    private func addInfoLog(_ message: String) {
        addLog(message, color: .neonBlue)
    }
    
    private func addSuccessLog(_ message: String) {
        addLog(message, color: .neonGreen)
    }
    
    private func addWarningLog(_ message: String) {
        addLog(message, color: .neonOrange)
    }
    
    private func addErrorLog(_ message: String) {
        addLog(message, color: .neonRed)
    }
    
    private func addLog(_ message: String, color: Color) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        
        Task { @MainActor in
            debugLogs.append(DebugLogEntry(
                timestamp: timestamp,
                message: message,
                color: color
            ))
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

struct DebugLogEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let message: String
    let color: Color
}

#Preview {
    DebugConsoleView()
        .environmentObject(TunnelManager.shared)
        .environmentObject(AppState.shared)
        .environmentObject(LogStore.shared)
}
