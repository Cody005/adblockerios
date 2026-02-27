//
//  Components.swift
//  ShadowGuard
//
//  Reusable UI components with futuristic styling
//

import SwiftUI

// MARK: - Power Button
struct PowerButton: View {
    @Binding var isOn: Bool
    var size: CGFloat = 120
    var onColor: Color = .neonGreen
    var offColor: Color = .neonRed
    var action: () -> Void
    
    @State private var isAnimating = false
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                action()
            }
        }) {
            ZStack {
                // Outer glow ring
                Circle()
                    .stroke(
                        isOn ? onColor.opacity(0.3) : offColor.opacity(0.2),
                        lineWidth: 2
                    )
                    .frame(width: size * 1.3, height: size * 1.3)
                    .scaleEffect(pulseScale)
                
                // Background circle
                Circle()
                    .fill(Color.shadowCard)
                    .frame(width: size, height: size)
                
                // Gradient overlay
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                (isOn ? onColor : offColor).opacity(0.3),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size / 2
                        )
                    )
                    .frame(width: size, height: size)
                
                // Border
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                (isOn ? onColor : offColor).opacity(0.8),
                                (isOn ? onColor : offColor).opacity(0.3)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 3
                    )
                    .frame(width: size, height: size)
                
                // Power icon
                Image(systemName: "power")
                    .font(.system(size: size * 0.35, weight: .medium))
                    .foregroundColor(isOn ? onColor : offColor)
                    .shadow(color: (isOn ? onColor : offColor).opacity(0.8), radius: 10)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            if isOn {
                startPulseAnimation()
            }
        }
        .onChange(of: isOn) { _, newValue in
            if newValue {
                startPulseAnimation()
            } else {
                pulseScale = 1.0
            }
        }
    }
    
    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.1
        }
    }
}

// MARK: - Stats Card
struct StatsCard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .neonCyan
    var subtitle: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
            
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(glowColor: color, glowRadius: 4)
    }
}

// MARK: - Progress Ring
struct ProgressRing: View {
    var progress: Double
    var size: CGFloat = 150
    var lineWidth: CGFloat = 12
    var gradientColors: [Color] = [.neonCyan, .neonPurple]
    var label: String?
    
    @State private var animatedProgress: Double = 0
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.shadowCard, lineWidth: lineWidth)
                .frame(width: size, height: size)
            
            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: gradientColors + [gradientColors.first!],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .shadow(color: gradientColors.first!.opacity(0.5), radius: 8)
            
            // Center content
            VStack(spacing: 4) {
                Text("\(Int(animatedProgress * 100))%")
                    .font(.system(size: size * 0.2, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                
                if let label = label {
                    Text(label)
                        .font(.system(size: size * 0.08, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeOut(duration: 0.5)) {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    var icon: String?
    var action: (() -> Void)?
    var actionLabel: String?
    
    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.neonCyan)
            }
            
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
                .tracking(1.5)
            
            Spacer()
            
            if let action = action, let actionLabel = actionLabel {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.neonCyan)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - List Row
struct CyberListRow: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var iconColor: Color = .neonCyan
    var trailing: AnyView?
    var action: (() -> Void)?
    
    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 14) {
                if let icon = icon {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(iconColor)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.textPrimary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.textSecondary)
                    }
                }
                
                Spacer()
                
                if let trailing = trailing {
                    trailing
                } else if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
            }
            .padding(14)
            .background(Color.shadowCard.opacity(0.5))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Badge
struct CyberBadge: View {
    let text: String
    var color: Color = .neonCyan
    var size: BadgeSize = .medium
    
    enum BadgeSize {
        case small, medium, large
        
        var fontSize: CGFloat {
            switch self {
            case .small: return 10
            case .medium: return 12
            case .large: return 14
            }
        }
        
        var padding: EdgeInsets {
            switch self {
            case .small: return EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6)
            case .medium: return EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            case .large: return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            }
        }
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: size.fontSize, weight: .semibold))
            .foregroundColor(color)
            .padding(size.padding)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)?
    var actionLabel: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.textTertiary)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)
                
                Text(message)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            if let action = action, let actionLabel = actionLabel {
                Button(action: action) {
                    Text(actionLabel)
                }
                .buttonStyle(CyberButtonStyle())
            }
        }
        .padding(32)
    }
}

// MARK: - Loading Indicator
struct CyberLoadingIndicator: View {
    @State private var rotation: Double = 0
    var size: CGFloat = 40
    var color: Color = .neonCyan
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 3)
                .frame(width: size, height: size)
            
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    LinearGradient(
                        colors: [color, color.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(rotation))
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Search Bar
struct CyberSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var onSubmit: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.textTertiary)
            
            TextField(placeholder, text: $text)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    onSubmit?()
                }
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.shadowCard)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.glassBorder, lineWidth: 1)
        )
    }
}

// MARK: - Chip/Tag
struct CyberChip: View {
    let label: String
    var isSelected: Bool = false
    var color: Color = .neonCyan
    var action: (() -> Void)?
    
    var body: some View {
        Button(action: { action?() }) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .shadowBackground : color)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? color : color.opacity(0.1))
                )
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Alert Banner
struct AlertBanner: View {
    let message: String
    var type: AlertType = .info
    var action: (() -> Void)?
    
    enum AlertType {
        case info, warning, error, success
        
        var color: Color {
            switch self {
            case .info: return .neonCyan
            case .warning: return .neonOrange
            case .error: return .neonRed
            case .success: return .neonGreen
            }
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .success: return "checkmark.circle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(type.color)
            
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textPrimary)
                .lineLimit(2)
            
            Spacer()
            
            if let action = action {
                Button(action: action) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(type.color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(type.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Divider
struct CyberDivider: View {
    var color: Color = .glassBorder
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, color, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}
