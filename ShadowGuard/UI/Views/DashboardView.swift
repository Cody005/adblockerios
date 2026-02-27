//
//  DashboardView.swift
//  ShadowGuard
//
//  Main dashboard with protection toggle and stats
//  Uses MITM proxy for HTTPS content filtering + DNS blocking
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tunnelManager: TunnelManager
    @StateObject private var blocklistManager = BlocklistManager.shared
    @State private var showingBlocklistUpdate = false
    @State private var showingCAWizard = false
    @State private var isPaused = false
    @State private var isAnimating = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Status Header
                    statusHeader
                    
                    // CA Warning Banner (if not trusted)
                    if !appState.isCATrusted {
                        caWarningBanner
                    }
                    
                    // Power Button
                    powerButtonSection
                    
                    // Protection Level Ring
                    protectionRing
                    
                    // Quick Stats
                    statsGrid
                    
                    // Top Blocked Domains
                    topBlockedSection
                    
                    // Blocklist Status
                    blocklistStatusSection
                    
                    // Quick Actions
                    quickActionsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .background(Color.clear)
            .navigationTitle("ShadowGuard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showingBlocklistUpdate = true }) {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundColor(.neonCyan)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingCAWizard = true }) {
                        Image(systemName: "key.fill")
                            .foregroundColor(appState.isCATrusted ? .neonGreen : .neonOrange)
                    }
                }
            }
        }
        .sheet(isPresented: $showingBlocklistUpdate) {
            BlocklistUpdateSheet()
        }
        .sheet(isPresented: $showingCAWizard) {
            CAInstallationWizard()
        }
    }
    
    // MARK: - CA Warning Banner
    private var caWarningBanner: some View {
        Button(action: { showingCAWizard = true }) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.neonOrange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Certificate Not Installed")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("Tap to install for HTTPS ad blocking")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.textTertiary)
            }
            .padding(16)
            .glassCard(glowColor: .neonOrange, glowRadius: 4)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Blocklist Status
    private var blocklistStatusSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Filter Status", icon: "line.3.horizontal.decrease.circle")
            
            HStack(spacing: 16) {
                // Rules count
                VStack(spacing: 4) {
                    Text("\(blocklistManager.totalRuleCount)")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.neonCyan)
                    Text("Rules Active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .glassCard()
                
                // Last update
                VStack(spacing: 4) {
                    Text(lastUpdateText)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.neonGreen)
                    Text("Last Update")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .glassCard()
            }
        }
    }
    
    private var lastUpdateText: String {
        guard let date = blocklistManager.lastUpdateDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Quick Actions
    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Quick Actions", icon: "bolt.fill")
            
            HStack(spacing: 12) {
                // Pause/Resume
                Button(action: togglePause) {
                    HStack {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        Text(isPaused ? "Resume" : "Pause")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CyberButtonStyle(primaryColor: isPaused ? .neonGreen : .neonOrange, size: .small))
                
                // Update Lists
                Button(action: updateLists) {
                    HStack {
                        if blocklistManager.isUpdating {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Update")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(CyberButtonStyle(primaryColor: .neonCyan, size: .small))
                .disabled(blocklistManager.isUpdating)
            }
        }
    }
    
    private func togglePause() {
        isPaused.toggle()
        Task {
            try? await tunnelManager.sendCommand(isPaused ? "pause" : "resume")
        }
    }
    
    private func updateLists() {
        Task {
            await blocklistManager.updateAllLists()
        }
    }
    
    // MARK: - Status Header
    private var statusHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(tunnelManager.isConnected ? "Protection Active" : "Protection Inactive")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                
                Text(tunnelManager.statusDescription)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(tunnelManager.isConnected ? .neonGreen : .textSecondary)
            }
            
            Spacer()
            
            // Status indicator
            Circle()
                .fill(tunnelManager.isConnected ? Color.neonGreen : Color.textTertiary)
                .frame(width: 12, height: 12)
                .shadow(color: tunnelManager.isConnected ? .neonGreen.opacity(0.8) : .clear, radius: 8)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: tunnelManager.isConnected)
        }
        .padding(20)
        .glassCard(glowColor: tunnelManager.isConnected ? .neonGreen : .neonCyan, glowRadius: tunnelManager.isConnected ? 8 : 0)
    }
    
    // MARK: - Power Button
    private var powerButtonSection: some View {
        VStack(spacing: 16) {
            PowerButton(
                isOn: .init(
                    get: { tunnelManager.isConnected },
                    set: { _ in }
                ),
                size: 140,
                onColor: .neonGreen,
                offColor: .neonRed
            ) {
                Task {
                    do {
                        try await tunnelManager.toggleTunnel()
                    } catch {
                        // Error handled by TunnelManager
                    }
                }
            }
            .disabled(tunnelManager.isLoading)
            
            if tunnelManager.isLoading {
                CyberLoadingIndicator(size: 30)
            }
            
            Text(tunnelManager.isConnected ? "Tap to disable protection" : "Tap to enable protection")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Protection Ring
    private var protectionRing: some View {
        VStack(spacing: 12) {
            ProgressRing(
                progress: appState.protectionLevel,
                size: 120,
                lineWidth: 10,
                gradientColors: protectionGradientColors,
                label: "Protected"
            )
            
            Text(protectionLevelText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
        }
        .padding(20)
        .glassCard()
    }
    
    private var protectionGradientColors: [Color] {
        if appState.protectionLevel >= 0.8 {
            return [.neonGreen, .neonCyan]
        } else if appState.protectionLevel >= 0.5 {
            return [.neonCyan, .neonBlue]
        } else if appState.protectionLevel >= 0.3 {
            return [.neonOrange, .neonYellow]
        } else {
            return [.neonRed, .neonOrange]
        }
    }
    
    private var protectionLevelText: String {
        if appState.protectionLevel >= 0.8 {
            return "Maximum protection enabled"
        } else if appState.protectionLevel >= 0.5 {
            return "Good protection level"
        } else if appState.protectionLevel >= 0.3 {
            return "Basic protection - enable more filters"
        } else {
            return "Low protection - configure settings"
        }
    }
    
    // MARK: - Stats Grid
    private var statsGrid: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Today's Stats", icon: "chart.bar.fill")
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                StatsCard(
                    title: "Blocked Today",
                    value: formatNumber(appState.blockedToday),
                    icon: "xmark.shield.fill",
                    color: .neonPink
                )
                
                StatsCard(
                    title: "Total Blocked",
                    value: formatNumber(appState.blockedTotal),
                    icon: "shield.checkered",
                    color: .neonCyan
                )
                
                StatsCard(
                    title: "Data Saved",
                    value: formatBytes(appState.savedBandwidth),
                    icon: "arrow.down.circle.fill",
                    color: .neonGreen
                )
                
                StatsCard(
                    title: "Active Filters",
                    value: "\(FilterEngine.shared.builtInLists.filter { $0.isEnabled }.count)",
                    icon: "line.3.horizontal.decrease.circle.fill",
                    color: .neonPurple
                )
            }
        }
    }
    
    // MARK: - Top Blocked Domains
    private var topBlockedSection: some View {
        VStack(spacing: 12) {
            SectionHeader(
                title: "Top Blocked Domains",
                icon: "list.number",
                action: { },
                actionLabel: "See All"
            )
            
            if appState.topBlockedDomains.isEmpty {
                EmptyStateView(
                    icon: "shield.slash",
                    title: "No blocked domains yet",
                    message: "Start browsing to see blocked trackers and ads"
                )
                .frame(height: 150)
            } else {
                VStack(spacing: 8) {
                    ForEach(appState.topBlockedDomains.prefix(5)) { domain in
                        HStack {
                            Circle()
                                .fill(Color.neonPink.opacity(0.3))
                                .frame(width: 8, height: 8)
                            
                            Text(domain.domain)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text("\(domain.count)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.neonPink)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.shadowCard.opacity(0.5))
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding(16)
        .glassCard()
    }
    
    // MARK: - CA Warning Banner
    private var caWarningBanner: some View {
        Button(action: { showingCAWizard = true }) {
            AlertBanner(
                message: "Certificate not trusted. Tap to complete setup.",
                type: .warning
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helpers
    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        }
        return "\(number)"
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - CA Installation Wizard
struct CAInstallationWizard: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var isGeneratingCA = false
    @State private var caGenerated = false
    @State private var errorMessage: String?
    
    private let steps = [
        WizardStep(
            title: "Generate Certificate",
            description: "First, we'll create a unique root certificate for your device.",
            icon: "key.fill",
            action: "Generate CA"
        ),
        WizardStep(
            title: "Install Profile",
            description: "Download and install the configuration profile containing your certificate.",
            icon: "square.and.arrow.down.fill",
            action: "Install Profile"
        ),
        WizardStep(
            title: "Trust Certificate",
            description: "Go to Settings → General → About → Certificate Trust Settings and enable full trust for ShadowGuard Root CA.",
            icon: "checkmark.shield.fill",
            action: "Open Settings"
        )
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                
                VStack(spacing: 24) {
                    // Progress indicator
                    HStack(spacing: 8) {
                        ForEach(0..<steps.count, id: \.self) { index in
                            Capsule()
                                .fill(index <= currentStep ? Color.neonCyan : Color.shadowCard)
                                .frame(height: 4)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Current step content
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color.neonCyan.opacity(0.2))
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: steps[currentStep].icon)
                                .font(.system(size: 40, weight: .medium))
                                .foregroundColor(.neonCyan)
                        }
                        
                        Text(steps[currentStep].title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.textPrimary)
                        
                        Text(steps[currentStep].description)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        if let error = errorMessage {
                            AlertBanner(message: error, type: .error) {
                                errorMessage = nil
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 40)
                    
                    Spacer()
                    
                    // Action button
                    Button(action: performStepAction) {
                        HStack {
                            if isGeneratingCA {
                                CyberLoadingIndicator(size: 20, color: .shadowBackground)
                            }
                            Text(steps[currentStep].action)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CyberButtonStyle(primaryColor: .neonCyan, size: .large))
                    .disabled(isGeneratingCA)
                    .padding(.horizontal, 32)
                    
                    // Skip/Back buttons
                    HStack {
                        if currentStep > 0 {
                            Button("Back") {
                                withAnimation {
                                    currentStep -= 1
                                }
                            }
                            .foregroundColor(.textSecondary)
                        }
                        
                        Spacer()
                        
                        if currentStep < steps.count - 1 {
                            Button("Skip") {
                                withAnimation {
                                    currentStep += 1
                                }
                            }
                            .foregroundColor(.textSecondary)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Setup Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.neonCyan)
                }
            }
        }
    }
    
    private func performStepAction() {
        switch currentStep {
        case 0:
            generateCA()
        case 1:
            installProfile()
        case 2:
            openSettings()
        default:
            break
        }
    }
    
    private func generateCA() {
        isGeneratingCA = true
        errorMessage = nil
        
        Task {
            do {
                _ = try await CertificateManager.shared.loadOrCreateRootCA()
                
                await MainActor.run {
                    isGeneratingCA = false
                    caGenerated = true
                    withAnimation {
                        currentStep = 1
                    }
                }
            } catch {
                await MainActor.run {
                    isGeneratingCA = false
                    errorMessage = "Failed to generate certificate: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func installProfile() {
        Task {
            do {
                let pemData = try await CertificateManager.shared.getRootCertificatePEM()
                
                // Save to a file that can be shared
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let profileURL = documentsURL.appendingPathComponent("ShadowGuard-CA.pem")
                try pemData.write(to: profileURL, atomically: true, encoding: .utf8)
                
                // In a real implementation, we'd create a .mobileconfig profile
                // and open it with UIApplication.shared.open()
                
                await MainActor.run {
                    withAnimation {
                        currentStep = 2
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to create profile: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        dismiss()
    }
}

struct WizardStep {
    let title: String
    let description: String
    let icon: String
    let action: String
}

#Preview {
    DashboardView()
        .environmentObject(AppState.shared)
        .environmentObject(TunnelManager.shared)
        .preferredColorScheme(.dark)
}
