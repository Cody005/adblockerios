//
//  BlocklistUpdateSheet.swift
//  ShadowGuard
//
//  Sheet for managing and updating blocklists
//  Supports adding custom blocklist URLs from GitHub, etc.
//

import SwiftUI

struct BlocklistUpdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var blocklistManager = BlocklistManager.shared
    @State private var showingAddCustom = false
    @State private var customName = ""
    @State private var customURL = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Update Status
                        if blocklistManager.isUpdating {
                            updateProgressSection
                        }
                        
                        // Error Message
                        if let error = blocklistManager.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.neonOrange)
                                Text(error)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.neonOrange)
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Update Button
                        Button(action: updateAll) {
                            HStack {
                                if blocklistManager.isUpdating {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text(blocklistManager.isUpdating ? "Updating..." : "Update All Lists")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CyberButtonStyle())
                        .disabled(blocklistManager.isUpdating)
                        .padding(.horizontal, 20)
                        
                        // Last Update Info
                        if let lastUpdate = blocklistManager.lastUpdateDate {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(.textSecondary)
                                Text("Last updated: \(lastUpdate, formatter: dateFormatter)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        
                        // Add Custom Blocklist Button
                        Button(action: { showingAddCustom = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.neonGreen)
                                Text("Add Custom Blocklist URL")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.textTertiary)
                            }
                            .padding(16)
                            .glassCard()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        
                        // Custom Blocklists Section
                        if !blocklistManager.customSources.isEmpty {
                            customBlocklistsSection
                        }
                        
                        // Built-in Blocklist Sources
                        ForEach(BlocklistManager.BlocklistSource.Category.allCases.filter { $0 != .custom }, id: \.self) { category in
                            categorySection(category)
                        }
                    }
                    .padding(.vertical, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Blocklists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.neonCyan)
                }
            }
            .sheet(isPresented: $showingAddCustom) {
                addCustomBlocklistSheet
            }
        }
    }
    
    // MARK: - Add Custom Blocklist Sheet
    private var addCustomBlocklistSheet: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textSecondary)
                        
                        TextField("My Custom List", text: $customName)
                            .textFieldStyle(CyberTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("URL")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textSecondary)
                        
                        TextField("https://raw.githubusercontent.com/...", text: $customURL)
                            .textFieldStyle(CyberTextFieldStyle())
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    
                    Text("Supports hosts files, AdBlock Plus format, and domain lists")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                    
                    Button(action: addCustomBlocklist) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Blocklist")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CyberButtonStyle())
                    .disabled(customName.isEmpty || customURL.isEmpty)
                }
                .padding(20)
            }
            .navigationTitle("Add Custom Blocklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showingAddCustom = false
                        customName = ""
                        customURL = ""
                    }
                    .foregroundColor(.textSecondary)
                }
            }
        }
    }
    
    // MARK: - Custom Blocklists Section
    private var customBlocklistsSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Custom Lists", icon: "link")
                .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                ForEach(blocklistManager.customSources) { source in
                    customSourceRow(source)
                    
                    if source.id != blocklistManager.customSources.last?.id {
                        CyberDivider()
                            .padding(.horizontal, 16)
                    }
                }
            }
            .glassCard()
            .padding(.horizontal, 20)
        }
    }
    
    private func customSourceRow(_ source: BlocklistManager.BlocklistSource) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.textPrimary)
                
                Text(source.url)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if source.ruleCount > 0 {
                        Text("\(source.ruleCount) rules")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.neonCyan)
                    }
                    
                    if let lastUpdated = source.lastUpdated {
                        Text("Updated \(lastUpdated, formatter: shortDateFormatter)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            // Delete button
            Button(action: { blocklistManager.removeCustomBlocklist(source.id) }) {
                Image(systemName: "trash")
                    .foregroundColor(.neonRed)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            
            Toggle("", isOn: Binding(
                get: { source.isEnabled },
                set: { _ in blocklistManager.toggleSource(source.id) }
            ))
            .toggleStyle(NeonToggleStyle())
            .labelsHidden()
        }
        .padding(16)
    }
    
    private func addCustomBlocklist() {
        guard !customName.isEmpty, !customURL.isEmpty else { return }
        
        blocklistManager.addCustomBlocklist(name: customName, url: customURL)
        
        customName = ""
        customURL = ""
        showingAddCustom = false
    }
    
    // MARK: - Update Progress
    private var updateProgressSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: blocklistManager.updateProgress)
                .tint(.neonCyan)
            
            Text("\(Int(blocklistManager.updateProgress * 100))% Complete")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Category Section
    private func categorySection(_ category: BlocklistManager.BlocklistSource.Category) -> some View {
        let sources = blocklistManager.sources.filter { $0.category == category }
        guard !sources.isEmpty else { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(spacing: 12) {
                SectionHeader(title: category.rawValue, icon: categoryIcon(category))
                    .padding(.horizontal, 20)
                
                VStack(spacing: 0) {
                    ForEach(sources) { source in
                        sourceRow(source)
                        
                        if source.id != sources.last?.id {
                            CyberDivider()
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .glassCard()
                .padding(.horizontal, 20)
            }
        )
    }
    
    private func sourceRow(_ source: BlocklistManager.BlocklistSource) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.textPrimary)
                
                HStack(spacing: 8) {
                    if source.ruleCount > 0 {
                        Text("\(source.ruleCount) rules")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.neonCyan)
                    }
                    
                    if let lastUpdated = source.lastUpdated {
                        Text("Updated \(lastUpdated, formatter: shortDateFormatter)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { source.isEnabled },
                set: { _ in blocklistManager.toggleSource(source.id) }
            ))
            .toggleStyle(NeonToggleStyle())
            .labelsHidden()
        }
        .padding(16)
    }
    
    // MARK: - Helpers
    private func categoryIcon(_ category: BlocklistManager.BlocklistSource.Category) -> String {
        switch category {
        case .ads: return "nosign"
        case .privacy: return "eye.slash"
        case .security: return "shield"
        case .social: return "person.2"
        case .annoyances: return "xmark.circle"
        case .custom: return "link"
        }
    }
    
    private func updateAll() {
        Task {
            await blocklistManager.updateAllLists()
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    private var shortDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }
}

#Preview {
    BlocklistUpdateSheet()
        .preferredColorScheme(.dark)
}
