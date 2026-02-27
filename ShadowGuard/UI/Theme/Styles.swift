//
//  Styles.swift
//  ShadowGuard
//
//  Custom view modifiers and styles for futuristic UI
//

import SwiftUI

// MARK: - Glass Card Modifier
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var borderWidth: CGFloat = 1
    var glowColor: Color = .neonCyan
    var glowRadius: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.glassBackground)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)
                            .opacity(0.3)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.glassBorder, lineWidth: borderWidth)
            )
            .shadow(color: glowColor.opacity(glowRadius > 0 ? 0.3 : 0), radius: glowRadius)
    }
}

// MARK: - Neon Glow Modifier
struct NeonGlowModifier: ViewModifier {
    var color: Color
    var radius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.8), radius: radius / 2)
            .shadow(color: color.opacity(0.5), radius: radius)
            .shadow(color: color.opacity(0.3), radius: radius * 1.5)
    }
}

// MARK: - Neumorphic Button Style
struct NeumorphicButtonStyle: ButtonStyle {
    var color: Color = .neonCyan
    var isActive: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.shadowCard)
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.1),
                                    Color.black.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isActive ? color.opacity(0.5) : Color.glassBorder,
                        lineWidth: 1
                    )
            )
            .shadow(color: isActive ? color.opacity(0.3) : .clear, radius: 8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Cyber Button Style
struct CyberButtonStyle: ButtonStyle {
    var primaryColor: Color = .neonCyan
    var size: ButtonSize = .medium
    
    enum ButtonSize {
        case small, medium, large
        
        var padding: EdgeInsets {
            switch self {
            case .small: return EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            case .medium: return EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
            case .large: return EdgeInsets(top: 16, leading: 32, bottom: 16, trailing: 32)
            }
        }
        
        var fontSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 16
            case .large: return 18
            }
        }
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size.fontSize, weight: .semibold, design: .rounded))
            .foregroundColor(primaryColor)
            .padding(size.padding)
            .background(
                ZStack {
                    // Base
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.shadowCard)
                    
                    // Gradient overlay
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [primaryColor.opacity(0.2), primaryColor.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Corner accents
                    GeometryReader { geo in
                        Path { path in
                            let w = geo.size.width
                            let h = geo.size.height
                            let corner: CGFloat = 8
                            
                            // Top left
                            path.move(to: CGPoint(x: 0, y: corner))
                            path.addLine(to: CGPoint(x: 0, y: 0))
                            path.addLine(to: CGPoint(x: corner, y: 0))
                            
                            // Top right
                            path.move(to: CGPoint(x: w - corner, y: 0))
                            path.addLine(to: CGPoint(x: w, y: 0))
                            path.addLine(to: CGPoint(x: w, y: corner))
                            
                            // Bottom right
                            path.move(to: CGPoint(x: w, y: h - corner))
                            path.addLine(to: CGPoint(x: w, y: h))
                            path.addLine(to: CGPoint(x: w - corner, y: h))
                            
                            // Bottom left
                            path.move(to: CGPoint(x: corner, y: h))
                            path.addLine(to: CGPoint(x: 0, y: h))
                            path.addLine(to: CGPoint(x: 0, y: h - corner))
                        }
                        .stroke(primaryColor, lineWidth: 2)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(primaryColor.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: primaryColor.opacity(0.4), radius: configuration.isPressed ? 4 : 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Toggle Style
struct NeonToggleStyle: ToggleStyle {
    var onColor: Color = .neonGreen
    var offColor: Color = .textTertiary
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            
            Spacer()
            
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? onColor.opacity(0.3) : Color.shadowCard)
                    .frame(width: 50, height: 30)
                
                Capsule()
                    .stroke(configuration.isOn ? onColor : offColor, lineWidth: 1)
                    .frame(width: 50, height: 30)
                
                Circle()
                    .fill(configuration.isOn ? onColor : offColor)
                    .frame(width: 24, height: 24)
                    .shadow(color: configuration.isOn ? onColor.opacity(0.5) : .clear, radius: 4)
                    .offset(x: configuration.isOn ? 10 : -10)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}

// MARK: - Text Field Style
struct CyberTextFieldStyle: TextFieldStyle {
    var icon: String?
    var accentColor: Color = .neonCyan
    @FocusState private var isFocused: Bool
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(accentColor)
                    .frame(width: 20)
            }
            
            configuration
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.shadowCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - View Extensions
extension View {
    func glassCard(
        cornerRadius: CGFloat = 20,
        borderWidth: CGFloat = 1,
        glowColor: Color = .neonCyan,
        glowRadius: CGFloat = 0
    ) -> some View {
        modifier(GlassCardModifier(
            cornerRadius: cornerRadius,
            borderWidth: borderWidth,
            glowColor: glowColor,
            glowRadius: glowRadius
        ))
    }
    
    func neonGlow(color: Color = .neonCyan, radius: CGFloat = 10) -> some View {
        modifier(NeonGlowModifier(color: color, radius: radius))
    }
    
    func cyberBorder(color: Color = .neonCyan, width: CGFloat = 1) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.5), lineWidth: width)
        )
    }
}

// MARK: - Animated Background
struct AnimatedGradientBackground: View {
    @State private var animateGradient = false
    
    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient.backgroundGradient
            
            // Animated orbs
            GeometryReader { geo in
                Circle()
                    .fill(RadialGradient.glowCyan)
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(
                        x: animateGradient ? geo.size.width * 0.3 : geo.size.width * 0.7,
                        y: animateGradient ? geo.size.height * 0.2 : geo.size.height * 0.4
                    )
                
                Circle()
                    .fill(RadialGradient.glowPink)
                    .frame(width: 250, height: 250)
                    .blur(radius: 50)
                    .offset(
                        x: animateGradient ? geo.size.width * 0.6 : geo.size.width * 0.2,
                        y: animateGradient ? geo.size.height * 0.7 : geo.size.height * 0.5
                    )
                
                Circle()
                    .fill(RadialGradient.glowGreen)
                    .frame(width: 200, height: 200)
                    .blur(radius: 40)
                    .offset(
                        x: animateGradient ? geo.size.width * 0.1 : geo.size.width * 0.5,
                        y: animateGradient ? geo.size.height * 0.5 : geo.size.height * 0.8
                    )
            }
            .opacity(0.5)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

// MARK: - Particle Effect
struct ParticleEffect: View {
    let particleCount: Int
    @State private var particles: [Particle] = []
    
    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var opacity: Double
        var speed: Double
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(Color.neonCyan)
                        .frame(width: particle.size, height: particle.size)
                        .opacity(particle.opacity)
                        .position(x: particle.x, y: particle.y)
                }
            }
            .onAppear {
                generateParticles(in: geo.size)
                animateParticles(in: geo.size)
            }
        }
    }
    
    private func generateParticles(in size: CGSize) {
        particles = (0..<particleCount).map { _ in
            Particle(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height),
                size: CGFloat.random(in: 1...3),
                opacity: Double.random(in: 0.1...0.5),
                speed: Double.random(in: 0.5...2)
            )
        }
    }
    
    private func animateParticles(in size: CGSize) {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            for i in particles.indices {
                particles[i].y -= CGFloat(particles[i].speed)
                
                if particles[i].y < 0 {
                    particles[i].y = size.height
                    particles[i].x = CGFloat.random(in: 0...size.width)
                }
            }
        }
    }
}

// MARK: - Shimmer Effect
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.2),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: -geo.size.width + phase * geo.size.width * 2)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
