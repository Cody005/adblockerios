//
//  Colors.swift
//  ShadowGuard
//
//  Futuristic cyberpunk color palette
//

import SwiftUI

extension Color {
    // MARK: - Primary Colors
    static let neonCyan = Color(hex: "00F5FF")
    static let neonPink = Color(hex: "FF00FF")
    static let neonPurple = Color(hex: "BF00FF")
    static let neonBlue = Color(hex: "0080FF")
    static let neonGreen = Color(hex: "00FF88")
    static let neonOrange = Color(hex: "FF8800")
    static let neonRed = Color(hex: "FF3366")
    static let neonYellow = Color(hex: "FFFF00")
    
    // MARK: - Background Colors
    static let shadowBackground = Color(hex: "0A0A0F")
    static let shadowSurface = Color(hex: "12121A")
    static let shadowCard = Color(hex: "1A1A25")
    static let shadowElevated = Color(hex: "22222F")
    
    // MARK: - Gradient Colors
    static let gradientStart = Color(hex: "1A0A2E")
    static let gradientMiddle = Color(hex: "0F1624")
    static let gradientEnd = Color(hex: "0A0A0F")
    
    // MARK: - Text Colors
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "A0A0B0")
    static let textTertiary = Color(hex: "606070")
    
    // MARK: - Status Colors
    static let statusActive = Color.neonGreen
    static let statusInactive = Color.textTertiary
    static let statusWarning = Color.neonOrange
    static let statusError = Color.neonRed
    
    // MARK: - Glassmorphism
    static let glassBackground = Color.white.opacity(0.05)
    static let glassBorder = Color.white.opacity(0.1)
    static let glassHighlight = Color.white.opacity(0.15)
    
    // MARK: - Initializer
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Gradients
extension LinearGradient {
    static let neonCyanGradient = LinearGradient(
        colors: [Color.neonCyan, Color.neonBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let neonPinkGradient = LinearGradient(
        colors: [Color.neonPink, Color.neonPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let neonGreenGradient = LinearGradient(
        colors: [Color.neonGreen, Color.neonCyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let backgroundGradient = LinearGradient(
        colors: [Color.gradientStart, Color.gradientMiddle, Color.gradientEnd],
        startPoint: .top,
        endPoint: .bottom
    )
    
    static let cardGradient = LinearGradient(
        colors: [Color.shadowCard.opacity(0.8), Color.shadowSurface.opacity(0.6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let glassGradient = LinearGradient(
        colors: [Color.glassHighlight, Color.glassBackground],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Radial Gradients
extension RadialGradient {
    static let glowCyan = RadialGradient(
        colors: [Color.neonCyan.opacity(0.4), Color.clear],
        center: .center,
        startRadius: 0,
        endRadius: 150
    )
    
    static let glowPink = RadialGradient(
        colors: [Color.neonPink.opacity(0.4), Color.clear],
        center: .center,
        startRadius: 0,
        endRadius: 150
    )
    
    static let glowGreen = RadialGradient(
        colors: [Color.neonGreen.opacity(0.4), Color.clear],
        center: .center,
        startRadius: 0,
        endRadius: 150
    )
}
