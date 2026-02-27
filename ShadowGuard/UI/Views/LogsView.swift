//
//  LogsView.swift
//  ShadowGuard
//
//  Real-time traffic logs with filtering and search
//

import SwiftUI

struct LogsView: View {
    @EnvironmentObject var logStore: LogStore
    @State private var isAutoScrollEnabled = true
    @State private var showingFilters = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter chips
                filterChips
                
                // Search bar
                CyberSearchBar(text: $logStore.searchText, placeholder: "Search logs...")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                
                // Logs list
                if logStore.filteredLogs.isEmpty {
                    emptyState
                } else {
                    logsList
                }
            }
            .background(Color.clear)
            .navigationTitle("Traffic Logs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: { isAutoScrollEnabled.toggle() }) {
                            Label(
                                isAutoScrollEnabled ? "Disable Auto-scroll" : "Enable Auto-scroll",
                                systemImage: isAutoScrollEnabled ? "arrow.down.circle.fill" : "arrow.down.circle"
                            )
                        }
                        
                        Button(action: exportLogs) {
                            Label("Export Logs", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(role: .destructive, action: { logStore.clearLogs() }) {
                            Label("Clear Logs", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.neonCyan)
                    }
                }
            }
        }
    }
    
    // MARK: - Filter Chips
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LogEntry.LogType.allCases) { type in
                    FilterChip(
                        type: type,
                        isSelected: logStore.selectedTypes.contains(type)
                    ) {
                        if logStore.selectedTypes.contains(type) {
                            logStore.selectedTypes.remove(type)
                        } else {
                            logStore.selectedTypes.insert(type)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .background(Color.shadowSurface.opacity(0.5))
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(
                icon: "doc.text.magnifyingglass",
                title: "No logs yet",
                message: "Traffic logs will appear here when protection is active"
            )
            Spacer()
        }
    }
    
    // MARK: - Logs List
    private var logsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(logStore.filteredLogs) { entry in
                        LogEntryRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .padding(.bottom, 100)
            }
            .onChange(of: logStore.filteredLogs.count) { _, _ in
                if isAutoScrollEnabled, let firstLog = logStore.filteredLogs.first {
                    withAnimation {
                        proxy.scrollTo(firstLog.id, anchor: .top)
                    }
                }
            }
        }
    }
    
    private func exportLogs() {
        let logsText = logStore.exportLogs()
        let activityVC = UIActivityViewController(
            activityItems: [logsText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let type: LogEntry.LogType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 12, weight: .medium))
                
                Text(type.rawValue.capitalized)
                    .font(.system(size: 12, weight: .semibold))
                
                Text("\(countForType)")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.3)))
            }
            .foregroundColor(isSelected ? .shadowBackground : typeColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? typeColor : typeColor.opacity(0.15))
            )
            .overlay(
                Capsule()
                    .stroke(typeColor.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var typeColor: Color {
        switch type {
        case .blocked: return .neonPink
        case .allowed: return .neonGreen
        case .tls: return .neonCyan
        case .error: return .neonRed
        case .warning: return .neonOrange
        case .info: return .neonBlue
        }
    }
    
    private var countForType: Int {
        LogStore.shared.logs.filter { $0.type == type }.count
    }
}

// MARK: - Log Entry Row
struct LogEntryRow: View {
    let entry: LogEntry
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 10) {
                // Type indicator
                Circle()
                    .fill(typeColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: typeColor.opacity(0.5), radius: 4)
                
                // Timestamp
                Text(formattedTime)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.textTertiary)
                
                // Domain/Message
                if let domain = entry.domain {
                    Text(domain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                } else {
                    Text(entry.message)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Type badge
                Image(systemName: entry.type.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(typeColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            
            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    CyberDivider()
                        .padding(.horizontal, 12)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        detailRow("Type", entry.type.rawValue.capitalized)
                        detailRow("Time", entry.timestamp.formatted(date: .abbreviated, time: .standard))
                        detailRow("Message", entry.message)
                        
                        if let domain = entry.domain {
                            detailRow("Domain", domain)
                        }
                        
                        if let url = entry.url {
                            detailRow("URL", url)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.shadowCard.opacity(isExpanded ? 0.8 : 0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isExpanded ? typeColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
    
    private var typeColor: Color {
        switch entry.type {
        case .blocked: return .neonPink
        case .allowed: return .neonGreen
        case .tls: return .neonCyan
        case .error: return .neonRed
        case .warning: return .neonOrange
        case .info: return .neonBlue
        }
    }
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: entry.timestamp)
    }
    
    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.textTertiary)
                .tracking(1)
            
            Text(value)
                .font(.system(size: 12, weight: .regular, design: label == "URL" ? .monospaced : .default))
                .foregroundColor(.textSecondary)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    LogsView()
        .environmentObject(LogStore.shared)
        .preferredColorScheme(.dark)
}
