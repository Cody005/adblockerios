//
//  SettingsView.swift
//  ShadowGuard
//
//  App settings, CA management, and advanced configuration
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunnelManager: TunnelManager
    
    @AppStorage("proxyPort") private var proxyPort: Int = 8899
    @AppStorage("enableDNSOverHTTPS") private var enableDNSOverHTTPS: Bool = false
    @AppStorage("dohProvider") private var dohProvider: String = "cloudflare"
    @AppStorage("logLevel") private var logLevel: String = "info"
    @AppStorage("enableCosmeticFiltering") private var enableCosmeticFiltering: Bool = true
    
    @State private var showingCAWizard = false
    @State private var showingBypassDomains = false
    @State private var showingResetConfirmation = false
    @State private var showingDeleteCAConfirmation = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Certificate Section
                    certificateSection
                    
                    // Proxy Settings
                    proxySettingsSection
                    
                    // DNS Settings
                    dnsSettingsSection
                    
                    // Filtering Options
                    filteringSection
                    
                    // Bypass Domains
                    bypassSection
                    
                    // Advanced
                    advancedSection
                    
                    // Danger Zone
                    dangerZoneSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 100)
            }
            .background(Color.clear)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showingCAWizard) {
            CAInstallationWizard()
        }
        .sheet(isPresented: $showingBypassDomains) {
            BypassDomainsView()
        }
        .alert("Reset Tunnel", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetTunnel()
            }
        } message: {
            Text("This will remove the VPN configuration and stop all protection. You'll need to set it up again.")
        }
        .alert("Delete Certificate", isPresented: $showingDeleteCAConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCA()
            }
        } message: {
            Text("This will delete the root CA certificate. HTTPS interception will stop working until you generate a new one.")
        }
    }
    
    // MARK: - Certificate Section
    private var certificateSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Certificate Authority", icon: "key.fill")
            
            VStack(spacing: 12) {
                // CA Status
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Root CA Status")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        
                        Text(caStatusText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(caStatusColor)
                    }
                    
                    Spacer()
                    
                    Circle()
                        .fill(caStatusColor)
                        .frame(width: 12, height: 12)
                        .shadow(color: caStatusColor.opacity(0.5), radius: 4)
                }
                .padding(16)
                .glassCard(glowColor: caStatusColor, glowRadius: 4)
                
                // Actions
                Button(action: { showingCAWizard = true }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text(appState.isCAInstalled ? "Reinstall Certificate" : "Install Certificate")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CyberButtonStyle())
                
                if appState.isCAInstalled {
                    Button(action: exportCA) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export CA Certificate")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CyberButtonStyle(primaryColor: .neonGreen))
                }
            }
        }
    }
    
    private var caStatusText: String {
        if appState.isCATrusted {
            return "Installed and trusted"
        } else if appState.isCAInstalled {
            return "Installed but not trusted"
        } else {
            return "Not installed"
        }
    }
    
    private var caStatusColor: Color {
        if appState.isCATrusted {
            return .neonGreen
        } else if appState.isCAInstalled {
            return .neonOrange
        } else {
            return .neonRed
        }
    }
    
    // MARK: - Proxy Settings
    private var proxySettingsSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Proxy Settings", icon: "network")
            
            VStack(spacing: 0) {
                SettingsRow(
                    title: "Proxy Port",
                    subtitle: "Local proxy server port",
                    icon: "number",
                    trailing: AnyView(
                        Text("\(proxyPort)")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.neonCyan)
                    )
                )
                
                CyberDivider()
                    .padding(.horizontal, 16)
                
                SettingsRow(
                    title: "Connection Status",
                    subtitle: tunnelManager.statusDescription,
                    icon: "antenna.radiowaves.left.and.right",
                    trailing: AnyView(
                        Circle()
                            .fill(tunnelManager.isConnected ? Color.neonGreen : Color.textTertiary)
                            .frame(width: 10, height: 10)
                    )
                )
            }
            .glassCard()
        }
    }
    
    // MARK: - DNS Settings
    private var dnsSettingsSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "DNS Settings", icon: "globe")
            
            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: "DNS over HTTPS",
                    subtitle: "Encrypt DNS queries for privacy",
                    icon: "lock.shield",
                    isOn: $enableDNSOverHTTPS
                )
                
                if enableDNSOverHTTPS {
                    CyberDivider()
                        .padding(.horizontal, 16)
                    
                    SettingsPickerRow(
                        title: "DoH Provider",
                        icon: "server.rack",
                        selection: $dohProvider,
                        options: [
                            ("cloudflare", "Cloudflare"),
                            ("google", "Google"),
                            ("quad9", "Quad9"),
                            ("custom", "Custom")
                        ]
                    )
                }
            }
            .glassCard()
        }
    }
    
    // MARK: - Filtering Section
    private var filteringSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Filtering Options", icon: "line.3.horizontal.decrease.circle")
            
            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: "Cosmetic Filtering",
                    subtitle: "Hide page elements (experimental)",
                    icon: "eye.slash",
                    isOn: $enableCosmeticFiltering
                )
                
                CyberDivider()
                    .padding(.horizontal, 16)
                
                SettingsPickerRow(
                    title: "Log Level",
                    icon: "doc.text",
                    selection: $logLevel,
                    options: [
                        ("error", "Errors Only"),
                        ("warning", "Warnings"),
                        ("info", "Info"),
                        ("debug", "Debug")
                    ]
                )
            }
            .glassCard()
        }
    }
    
    // MARK: - Bypass Section
    private var bypassSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Bypass Domains", icon: "arrow.triangle.branch")
            
            Button(action: { showingBypassDomains = true }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Manage Bypass List")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.textPrimary)
                        
                        Text("Domains that skip MITM interception")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
                .padding(16)
                .glassCard()
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Advanced Section
    private var advancedSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Advanced", icon: "gearshape.2")
            
            VStack(spacing: 0) {
                SettingsRow(
                    title: "App Group",
                    subtitle: "group.com.shadowguard.app",
                    icon: "folder",
                    trailing: nil
                )
                
                CyberDivider()
                    .padding(.horizontal, 16)
                
                SettingsRow(
                    title: "Tunnel Bundle ID",
                    subtitle: "com.shadowguard.app.tunnel",
                    icon: "shippingbox",
                    trailing: nil
                )
            }
            .glassCard()
        }
    }
    
    // MARK: - Danger Zone
    private var dangerZoneSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Danger Zone", icon: "exclamationmark.triangle")
            
            VStack(spacing: 12) {
                Button(action: { showingResetConfirmation = true }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Tunnel Configuration")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CyberButtonStyle(primaryColor: .neonOrange))
                
                Button(action: { showingDeleteCAConfirmation = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete Root CA")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CyberButtonStyle(primaryColor: .neonRed))
                
                Button(action: resetAllStats) {
                    HStack {
                        Image(systemName: "chart.bar.xaxis")
                        Text("Reset Statistics")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CyberButtonStyle(primaryColor: .neonPink))
            }
        }
    }
    
    // MARK: - Actions
    private func exportCA() {
        Task {
            do {
                let pemData = try await CertificateManager.shared.getRootCertificatePEM()
                
                let activityVC = UIActivityViewController(
                    activityItems: [pemData],
                    applicationActivities: nil
                )
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootVC = window.rootViewController {
                    rootVC.present(activityVC, animated: true)
                }
            } catch {
                // Handle error
            }
        }
    }
    
    private func resetTunnel() {
        Task {
            try? await tunnelManager.removeTunnel()
        }
    }
    
    private func deleteCA() {
        Task {
            try? CertificateManager.shared.deleteRootCA()
            await MainActor.run {
                appState.updateCAStatus(installed: false, trusted: false)
            }
        }
    }
    
    private func resetAllStats() {
        Task { @MainActor in
            appState.resetAllStats()
        }
    }
}

// MARK: - Settings Row Components
struct SettingsRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let trailing: AnyView?
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.neonCyan.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.neonCyan)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.textPrimary)
                
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let trailing = trailing {
                trailing
            }
        }
        .padding(16)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.neonCyan.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.neonCyan)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.textPrimary)
                
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(NeonToggleStyle())
                .labelsHidden()
        }
        .padding(16)
    }
}

struct SettingsPickerRow<T: Hashable>: View {
    let title: String
    let icon: String
    @Binding var selection: T
    let options: [(T, String)]
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.neonCyan.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.neonCyan)
            }
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.textPrimary)
            
            Spacer()
            
            Menu {
                ForEach(options, id: \.0) { option in
                    Button(action: { selection = option.0 }) {
                        HStack {
                            Text(option.1)
                            if selection == option.0 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(options.first { $0.0 == selection }?.1 ?? "")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.neonCyan)
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.neonCyan)
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Bypass Domains View
struct BypassDomainsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("bypassDomains") private var bypassDomainsData: Data = Data()
    @State private var domains: [String] = []
    @State private var newDomain = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                
                VStack(spacing: 16) {
                    // Info banner
                    AlertBanner(
                        message: "These domains will bypass MITM interception. Use for apps with certificate pinning.",
                        type: .info
                    )
                    .padding(.horizontal, 20)
                    
                    // Add domain
                    HStack(spacing: 12) {
                        TextField("*.example.com", text: $newDomain)
                            .font(.system(size: 16, weight: .regular, design: .monospaced))
                            .foregroundColor(.textPrimary)
                            .padding(14)
                            .background(Color.shadowCard)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.glassBorder, lineWidth: 1)
                            )
                        
                        Button(action: addDomain) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .buttonStyle(CyberButtonStyle(size: .small))
                        .disabled(newDomain.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    
                    // Domains list
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(domains, id: \.self) { domain in
                                HStack {
                                    Text(domain)
                                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                                        .foregroundColor(.textPrimary)
                                    
                                    Spacer()
                                    
                                    Button(action: { removeDomain(domain) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.textTertiary)
                                    }
                                }
                                .padding(14)
                                .background(Color.shadowCard.opacity(0.5))
                                .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                    }
                }
                .padding(.top, 16)
            }
            .navigationTitle("Bypass Domains")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        saveDomains()
                        dismiss()
                    }
                    .foregroundColor(.neonCyan)
                }
            }
            .onAppear {
                loadDomains()
            }
        }
    }
    
    private func loadDomains() {
        if let decoded = try? JSONDecoder().decode([String].self, from: bypassDomainsData) {
            domains = decoded
        } else {
            // Default bypass domains
            domains = [
                "*.apple.com",
                "*.icloud.com",
                "*.banking.*",
                "*.bank.*"
            ]
        }
    }
    
    private func saveDomains() {
        if let encoded = try? JSONEncoder().encode(domains) {
            bypassDomainsData = encoded
        }
        
        // Also save to app group for tunnel
        if let userDefaults = UserDefaults(suiteName: "group.com.shadowguard.app") {
            userDefaults.set(domains, forKey: "bypassDomains")
        }
    }
    
    private func addDomain() {
        let trimmed = newDomain.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !domains.contains(trimmed) {
            domains.append(trimmed)
            newDomain = ""
        }
    }
    
    private func removeDomain(_ domain: String) {
        domains.removeAll { $0 == domain }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
        .environmentObject(TunnelManager.shared)
        .preferredColorScheme(.dark)
}
