//
//  AboutView.swift
//  ShadowGuard
//
//  About screen with app info, MITM warning, and help
//

import SwiftUI

struct AboutView: View {
    @State private var showingMITMInfo = false
    @State private var showingLegalDisclaimer = false
    
    private let appVersion = "1.0.0"
    private let buildNumber = "1"
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // App Header
                    appHeader
                    
                    // Warning Banner
                    warningBanner
                    
                    // How It Works
                    howItWorksSection
                    
                    // Features
                    featuresSection
                    
                    // Links
                    linksSection
                    
                    // Legal
                    legalSection
                    
                    // Credits
                    creditsSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 100)
            }
            .background(Color.clear)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showingMITMInfo) {
            MITMInfoSheet()
        }
        .sheet(isPresented: $showingLegalDisclaimer) {
            LegalDisclaimerSheet()
        }
    }
    
    // MARK: - App Header
    private var appHeader: some View {
        VStack(spacing: 16) {
            // App Icon
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.neonCyan.opacity(0.3), Color.neonPurple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "shield.checkered")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.neonCyan, .neonPurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(color: .neonCyan.opacity(0.3), radius: 20)
            
            VStack(spacing: 4) {
                Text("ShadowGuard")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.textPrimary)
                
                Text("MITM Ad Blocker & Privacy Shield")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.textTertiary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Warning Banner
    private var warningBanner: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.neonOrange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Important Security Notice")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.neonOrange)
                    
                    Text("This app performs man-in-the-middle interception of your network traffic.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.textSecondary)
                }
            }
            
            Button(action: { showingMITMInfo = true }) {
                Text("Learn More About MITM")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.neonOrange)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.neonOrange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.neonOrange.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - How It Works
    private var howItWorksSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "How It Works", icon: "gearshape.2")
            
            VStack(spacing: 16) {
                howItWorksStep(
                    number: 1,
                    title: "VPN Tunnel",
                    description: "Creates a local VPN tunnel to intercept all network traffic",
                    icon: "network"
                )
                
                howItWorksStep(
                    number: 2,
                    title: "TLS Interception",
                    description: "Decrypts HTTPS traffic using a trusted root certificate",
                    icon: "lock.open"
                )
                
                howItWorksStep(
                    number: 3,
                    title: "Content Filtering",
                    description: "Analyzes requests and blocks ads, trackers, and malware",
                    icon: "line.3.horizontal.decrease"
                )
                
                howItWorksStep(
                    number: 4,
                    title: "Re-encryption",
                    description: "Re-encrypts and forwards allowed traffic to its destination",
                    icon: "lock.fill"
                )
            }
            .padding(16)
            .glassCard()
        }
    }
    
    private func howItWorksStep(number: Int, title: String, description: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.neonCyan.opacity(0.2))
                    .frame(width: 36, height: 36)
                
                Text("\(number)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.neonCyan)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.neonCyan)
                    
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.textPrimary)
                }
                
                Text(description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Features
    private var featuresSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Features", icon: "star.fill")
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                FeatureCard(icon: "shield.checkered", title: "System-wide", color: .neonCyan)
                FeatureCard(icon: "lock.fill", title: "HTTPS Support", color: .neonGreen)
                FeatureCard(icon: "list.bullet", title: "Custom Rules", color: .neonPurple)
                FeatureCard(icon: "bolt.fill", title: "Real-time", color: .neonOrange)
                FeatureCard(icon: "eye.slash", title: "Privacy", color: .neonPink)
                FeatureCard(icon: "chart.bar", title: "Statistics", color: .neonBlue)
            }
        }
    }
    
    // MARK: - Links
    private var linksSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Resources", icon: "link")
            
            VStack(spacing: 0) {
                LinkRow(title: "Documentation", icon: "doc.text", url: nil)
                CyberDivider().padding(.horizontal, 16)
                LinkRow(title: "Report Issue", icon: "exclamationmark.bubble", url: nil)
                CyberDivider().padding(.horizontal, 16)
                LinkRow(title: "Privacy Policy", icon: "hand.raised", url: nil)
            }
            .glassCard()
        }
    }
    
    // MARK: - Legal
    private var legalSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Legal", icon: "doc.plaintext")
            
            Button(action: { showingLegalDisclaimer = true }) {
                HStack {
                    Image(systemName: "exclamationmark.shield")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.neonRed)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Legal Disclaimer")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.textPrimary)
                        
                        Text("Important information about usage")
                            .font(.system(size: 12, weight: .regular))
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
    
    // MARK: - Credits
    private var creditsSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Credits", icon: "heart.fill")
            
            VStack(spacing: 8) {
                Text("Built with ❤️ for personal use")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                
                Text("Powered by Swift, SwiftUI, and Network Extension")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.textTertiary)
                
                HStack(spacing: 16) {
                    CreditBadge(text: "Swift 6")
                    CreditBadge(text: "iOS 17+")
                    CreditBadge(text: "SwiftUI")
                }
                .padding(.top, 8)
            }
            .padding(20)
            .glassCard()
        }
    }
}

// MARK: - Feature Card
struct FeatureCard: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Link Row
struct LinkRow: View {
    let title: String
    let icon: String
    let url: URL?
    
    var body: some View {
        Button(action: {
            if let url = url {
                UIApplication.shared.open(url)
            }
        }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.neonCyan)
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.textPrimary)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Credit Badge
struct CreditBadge: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.neonCyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.neonCyan.opacity(0.15))
            )
            .overlay(
                Capsule()
                    .stroke(Color.neonCyan.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - MITM Info Sheet
struct MITMInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "lock.trianglebadge.exclamationmark")
                                .font(.system(size: 48, weight: .medium))
                                .foregroundColor(.neonOrange)
                            
                            Text("Understanding MITM")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        
                        // Content
                        infoSection(
                            title: "What is MITM?",
                            content: "Man-in-the-Middle (MITM) is a technique where a proxy sits between your device and the internet, intercepting and potentially modifying traffic. ShadowGuard uses this to inspect HTTPS traffic for ads and trackers."
                        )
                        
                        infoSection(
                            title: "How does it work?",
                            content: "ShadowGuard installs a root certificate on your device. When you visit HTTPS sites, ShadowGuard creates a new certificate for that site signed by its root CA, allowing it to decrypt, inspect, and re-encrypt the traffic."
                        )
                        
                        infoSection(
                            title: "Is it safe?",
                            content: "When used on your own device for ad blocking, yes. However, this same technique can be used maliciously by attackers. Never install root certificates from untrusted sources."
                        )
                        
                        infoSection(
                            title: "What about certificate pinning?",
                            content: "Some apps (especially banking apps) use certificate pinning, which means they only trust specific certificates. These apps will not work through MITM and are automatically bypassed."
                        )
                        
                        AlertBanner(
                            message: "Only use ShadowGuard on devices you own. Never use it to intercept others' traffic.",
                            type: .warning
                        )
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("MITM Explained")
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
    
    private func infoSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.neonCyan)
            
            Text(content)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.textSecondary)
                .lineSpacing(4)
        }
        .padding(16)
        .glassCard()
    }
}

// MARK: - Legal Disclaimer Sheet
struct LegalDisclaimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Legal Disclaimer")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .padding(.top, 20)
                        
                        disclaimerSection(
                            title: "Personal Use Only",
                            content: "ShadowGuard is designed for personal use on your own devices only. Using this app to intercept network traffic on devices you do not own or without explicit permission may be illegal in your jurisdiction."
                        )
                        
                        disclaimerSection(
                            title: "No Warranty",
                            content: "This software is provided \"as is\" without warranty of any kind. The developers are not responsible for any damages or issues arising from the use of this application."
                        )
                        
                        disclaimerSection(
                            title: "Security Risks",
                            content: "Installing a root certificate and enabling MITM interception carries inherent security risks. You are responsible for understanding these risks before using this application."
                        )
                        
                        disclaimerSection(
                            title: "Third-Party Services",
                            content: "Some apps and services may not function correctly when MITM interception is enabled. This is expected behavior for apps using certificate pinning."
                        )
                        
                        disclaimerSection(
                            title: "Data Privacy",
                            content: "All traffic interception occurs locally on your device. No data is sent to external servers. However, you should still exercise caution when handling sensitive information."
                        )
                        
                        Text("By using ShadowGuard, you acknowledge that you have read and understood this disclaimer.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.neonOrange)
                            .padding(16)
                            .glassCard(glowColor: .neonOrange, glowRadius: 4)
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Disclaimer")
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
    
    private func disclaimerSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)
            
            Text(content)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.textSecondary)
                .lineSpacing(3)
        }
        .padding(16)
        .glassCard()
    }
}

#Preview {
    AboutView()
        .preferredColorScheme(.dark)
}
