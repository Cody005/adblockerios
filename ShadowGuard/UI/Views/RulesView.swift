//
//  RulesView.swift
//  ShadowGuard
//
//  Filter rules management - built-in lists and custom rules
//

import SwiftUI

struct RulesView: View {
    @EnvironmentObject var filterEngine: FilterEngine
    @State private var selectedTab: RulesTab = .builtIn
    @State private var showingAddRule = false
    @State private var showingImportExport = false
    @State private var searchText = ""
    
    enum RulesTab: String, CaseIterable {
        case builtIn = "Built-in"
        case custom = "Custom"
        
        var icon: String {
            switch self {
            case .builtIn: return "list.bullet.rectangle.fill"
            case .custom: return "pencil.and.list.clipboard"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                tabSelector
                
                // Content
                ScrollView {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case .builtIn:
                            builtInListsSection
                        case .custom:
                            customRulesSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .padding(.bottom, 100)
                }
            }
            .background(Color.clear)
            .navigationTitle("Filter Rules")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: { showingAddRule = true }) {
                            Label("Add Custom Rule", systemImage: "plus")
                        }
                        
                        Button(action: { showingImportExport = true }) {
                            Label("Import/Export", systemImage: "square.and.arrow.up.on.square")
                        }
                        
                        Button(action: updateAllLists) {
                            Label("Update All Lists", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.neonCyan)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddRule) {
            RuleEditorView(mode: .add)
        }
        .sheet(isPresented: $showingImportExport) {
            ImportExportView()
        }
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(RulesTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14, weight: .medium))
                            
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(selectedTab == tab ? .neonCyan : .textSecondary)
                        
                        Rectangle()
                            .fill(selectedTab == tab ? Color.neonCyan : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .background(Color.shadowSurface.opacity(0.5))
    }
    
    // MARK: - Built-in Lists
    private var builtInListsSection: some View {
        VStack(spacing: 16) {
            // Update status
            if filterEngine.isLoading {
                HStack {
                    CyberLoadingIndicator(size: 20)
                    Text("Updating filter lists...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                .padding()
                .glassCard()
            }
            
            // Lists by category
            ForEach(FilterList.FilterCategory.allCases, id: \.self) { category in
                let listsInCategory = filterEngine.builtInLists.filter { $0.category == category }
                
                if !listsInCategory.isEmpty {
                    VStack(spacing: 12) {
                        SectionHeader(title: category.rawValue, icon: categoryIcon(category))
                        
                        ForEach(listsInCategory) { list in
                            FilterListRow(list: list) {
                                filterEngine.toggleList(list)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func categoryIcon(_ category: FilterList.FilterCategory) -> String {
        switch category {
        case .ads: return "eye.slash.fill"
        case .privacy: return "hand.raised.fill"
        case .security: return "lock.shield.fill"
        case .social: return "person.2.slash.fill"
        case .annoyances: return "bell.slash.fill"
        case .custom: return "star.fill"
        }
    }
    
    // MARK: - Custom Rules
    private var customRulesSection: some View {
        VStack(spacing: 16) {
            // Search bar
            CyberSearchBar(text: $searchText, placeholder: "Search rules...")
            
            // Add rule button
            Button(action: { showingAddRule = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                    
                    Text("Add Custom Rule")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Spacer()
                }
                .foregroundColor(.neonCyan)
                .padding(16)
                .glassCard(glowColor: .neonCyan, glowRadius: 4)
            }
            .buttonStyle(.plain)
            
            // Rules list
            if filteredCustomRules.isEmpty {
                EmptyStateView(
                    icon: "doc.text",
                    title: "No custom rules",
                    message: "Add your own blocking, allowing, or redirect rules",
                    action: { showingAddRule = true },
                    actionLabel: "Add Rule"
                )
                .padding(.vertical, 40)
            } else {
                ForEach(filteredCustomRules) { rule in
                    CustomRuleRow(rule: rule)
                }
            }
        }
    }
    
    private var filteredCustomRules: [CustomRule] {
        if searchText.isEmpty {
            return filterEngine.customRules
        }
        return filterEngine.customRules.filter {
            $0.pattern.localizedCaseInsensitiveContains(searchText) ||
            ($0.comment?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    private func updateAllLists() {
        Task {
            await filterEngine.updateAllLists()
        }
    }
}

// MARK: - Filter List Row
struct FilterListRow: View {
    let list: FilterList
    let onToggle: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Status indicator
                Circle()
                    .fill(list.isEnabled ? Color.neonGreen : Color.textTertiary)
                    .frame(width: 10, height: 10)
                    .shadow(color: list.isEnabled ? .neonGreen.opacity(0.5) : .clear, radius: 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    
                    Text(list.description)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.textSecondary)
                        .lineLimit(isExpanded ? nil : 1)
                }
                
                Spacer()
                
                Toggle("", isOn: .init(
                    get: { list.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(NeonToggleStyle())
                .labelsHidden()
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    isExpanded.toggle()
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    CyberDivider()
                    
                    HStack {
                        Label("\(list.ruleCount) rules", systemImage: "list.number")
                        Spacer()
                        if let lastUpdated = list.lastUpdated {
                            Label(lastUpdated.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color.shadowCard.opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(list.isEnabled ? Color.neonGreen.opacity(0.3) : Color.glassBorder, lineWidth: 1)
        )
    }
}

// MARK: - Custom Rule Row
struct CustomRuleRow: View {
    let rule: CustomRule
    @EnvironmentObject var filterEngine: FilterEngine
    @State private var showingEditor = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Type indicator
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(typeColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: typeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(typeColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.pattern)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    CyberBadge(text: rule.type.rawValue, color: typeColor, size: .small)
                    
                    if let comment = rule.comment, !comment.isEmpty {
                        Text(comment)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            Toggle("", isOn: .init(
                get: { rule.isEnabled },
                set: { newValue in
                    var updatedRule = rule
                    updatedRule.isEnabled = newValue
                    filterEngine.updateCustomRule(updatedRule)
                }
            ))
            .toggleStyle(NeonToggleStyle(onColor: typeColor))
            .labelsHidden()
        }
        .padding(14)
        .background(Color.shadowCard.opacity(0.5))
        .cornerRadius(12)
        .contextMenu {
            Button(action: { showingEditor = true }) {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive, action: {
                filterEngine.deleteCustomRule(rule)
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingEditor) {
            RuleEditorView(mode: .edit(rule))
        }
    }
    
    private var typeColor: Color {
        switch rule.type {
        case .block: return .neonPink
        case .allow: return .neonGreen
        case .redirect: return .neonOrange
        }
    }
    
    private var typeIcon: String {
        switch rule.type {
        case .block: return "xmark"
        case .allow: return "checkmark"
        case .redirect: return "arrow.triangle.turn.up.right.diamond"
        }
    }
}

// MARK: - Rule Editor
struct RuleEditorView: View {
    enum Mode {
        case add
        case edit(CustomRule)
    }
    
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var filterEngine: FilterEngine
    
    @State private var pattern = ""
    @State private var ruleType: CustomRule.RuleType = .block
    @State private var comment = ""
    @State private var redirectTarget = ""
    @State private var testURL = ""
    @State private var testResult: RuleTestResult?
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Pattern input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PATTERN")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .tracking(1.5)
                            
                            TextField("e.g., ||ads.example.com^", text: $pattern)
                                .font(.system(size: 16, weight: .regular, design: .monospaced))
                                .foregroundColor(.textPrimary)
                                .padding(16)
                                .background(Color.shadowCard)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.neonCyan.opacity(0.3), lineWidth: 1)
                                )
                        }
                        
                        // Rule type selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RULE TYPE")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .tracking(1.5)
                            
                            HStack(spacing: 12) {
                                ForEach(CustomRule.RuleType.allCases, id: \.self) { type in
                                    CyberChip(
                                        label: type.rawValue,
                                        isSelected: ruleType == type,
                                        color: chipColor(for: type)
                                    ) {
                                        ruleType = type
                                    }
                                }
                            }
                        }
                        
                        // Redirect target (if redirect type)
                        if ruleType == .redirect {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("REDIRECT TO")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textSecondary)
                                    .tracking(1.5)
                                
                                TextField("0.0.0.0 or custom IP", text: $redirectTarget)
                                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                                    .foregroundColor(.textPrimary)
                                    .padding(16)
                                    .background(Color.shadowCard)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.neonOrange.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                        
                        // Comment
                        VStack(alignment: .leading, spacing: 8) {
                            Text("COMMENT (OPTIONAL)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .tracking(1.5)
                            
                            TextField("Description of this rule", text: $comment)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.textPrimary)
                                .padding(16)
                                .background(Color.shadowCard)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.glassBorder, lineWidth: 1)
                                )
                        }
                        
                        CyberDivider()
                        
                        // Rule tester
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TEST RULE")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .tracking(1.5)
                            
                            HStack(spacing: 12) {
                                TextField("Enter URL to test", text: $testURL)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.textPrimary)
                                    .padding(12)
                                    .background(Color.shadowCard)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.glassBorder, lineWidth: 1)
                                    )
                                
                                Button(action: testRule) {
                                    Image(systemName: "play.fill")
                                        .foregroundColor(.neonCyan)
                                }
                                .buttonStyle(CyberButtonStyle(size: .small))
                            }
                            
                            if let result = testResult {
                                HStack {
                                    Image(systemName: result.matches ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(result.matches ? .neonGreen : .neonRed)
                                    
                                    Text(result.matches ? "Rule matches this URL" : (result.error ?? "Rule does not match"))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(result.matches ? .neonGreen : .textSecondary)
                                }
                                .padding(12)
                                .glassCard(glowColor: result.matches ? .neonGreen : .neonRed, glowRadius: 4)
                            }
                        }
                        
                        // Syntax help
                        syntaxHelp
                    }
                    .padding(20)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle(mode.isAdd ? "Add Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.textSecondary)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveRule()
                    }
                    .foregroundColor(.neonCyan)
                    .disabled(pattern.isEmpty)
                }
            }
            .onAppear {
                if case .edit(let rule) = mode {
                    pattern = rule.pattern
                    ruleType = rule.type
                    comment = rule.comment ?? ""
                    redirectTarget = rule.redirectTarget ?? ""
                }
            }
        }
    }
    
    private var syntaxHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SYNTAX HELP")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)
                .tracking(1.5)
            
            VStack(alignment: .leading, spacing: 8) {
                syntaxRow("||domain.com^", "Block domain and subdomains")
                syntaxRow("|https://", "Match URL start")
                syntaxRow("*", "Wildcard (any characters)")
                syntaxRow("^", "Separator (/, ?, #, or end)")
                syntaxRow("/regex/", "Regular expression")
                syntaxRow("@@||domain.com^", "Whitelist (use Allow type)")
            }
            .padding(16)
            .glassCard()
        }
    }
    
    private func syntaxRow(_ syntax: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(syntax)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.neonCyan)
                .frame(width: 120, alignment: .leading)
            
            Text(description)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.textSecondary)
        }
    }
    
    private func chipColor(for type: CustomRule.RuleType) -> Color {
        switch type {
        case .block: return .neonPink
        case .allow: return .neonGreen
        case .redirect: return .neonOrange
        }
    }
    
    private func testRule() {
        guard !pattern.isEmpty, !testURL.isEmpty else { return }
        testResult = filterEngine.testRule(pattern, against: testURL)
    }
    
    private func saveRule() {
        let rule = CustomRule(
            pattern: pattern,
            type: ruleType,
            isEnabled: true,
            comment: comment.isEmpty ? nil : comment,
            redirectTarget: ruleType == .redirect ? redirectTarget : nil
        )
        
        if case .edit(let existingRule) = mode {
            filterEngine.deleteCustomRule(existingRule)
        }
        
        filterEngine.addCustomRule(rule)
        dismiss()
    }
}

extension RuleEditorView.Mode {
    var isAdd: Bool {
        if case .add = self { return true }
        return false
    }
}

// MARK: - Import/Export View
struct ImportExportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var filterEngine: FilterEngine
    @State private var importText = ""
    @State private var showingExport = false
    @State private var exportedText = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                
                VStack(spacing: 24) {
                    // Import section
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Import Rules", icon: "square.and.arrow.down")
                        
                        TextEditor(text: $importText)
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .foregroundColor(.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(height: 200)
                            .padding(12)
                            .background(Color.shadowCard)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.glassBorder, lineWidth: 1)
                            )
                        
                        Button(action: importRules) {
                            Text("Import")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CyberButtonStyle())
                        .disabled(importText.isEmpty)
                    }
                    
                    CyberDivider()
                    
                    // Export section
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Export Rules", icon: "square.and.arrow.up")
                        
                        Button(action: exportRules) {
                            HStack {
                                Image(systemName: "doc.on.doc")
                                Text("Export Custom Rules")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CyberButtonStyle(primaryColor: .neonGreen))
                    }
                    
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Import/Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.neonCyan)
                }
            }
            .sheet(isPresented: $showingExport) {
                ShareSheet(items: [exportedText])
            }
        }
    }
    
    private func importRules() {
        filterEngine.importRules(importText)
        importText = ""
        dismiss()
    }
    
    private func exportRules() {
        exportedText = filterEngine.exportRules()
        showingExport = true
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    RulesView()
        .environmentObject(FilterEngine.shared)
        .preferredColorScheme(.dark)
}
