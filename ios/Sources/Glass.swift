import SwiftUI

/// Graphite backdrop with soft drifting light so the glass has something to blur.
struct Backdrop: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.09), Color(white: 0.02)], startPoint: .top, endPoint: .bottom)
            blob(Color(white: 1), 0.10, 380, x: drift ? -120 : -50, y: drift ? -320 : -250)
            blob(Color(red: 0.55, green: 0.65, blue: 0.85), 0.14, 320, x: drift ? 140 : 80, y: drift ? 40 : 130)
            blob(Color(white: 1), 0.06, 280, x: drift ? -70 : -140, y: drift ? 380 : 300)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) { drift = true } }
    }

    private func blob(_ color: Color, _ strength: Double, _ size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(color.opacity(strength)).frame(width: size, height: size).blur(radius: 90).offset(x: x, y: y)
    }
}

extension View {
    /// Liquid Glass on iOS 26, frosted material with a light rim before that.
    @ViewBuilder func glass(_ radius: CGFloat = 28, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint),
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            modifier(MaterialGlass(radius: radius, tint: tint))
        }
        #else
        modifier(MaterialGlass(radius: radius, tint: tint))
        #endif
    }

    /// A screen that already fits shouldn't rubber-band.
    @ViewBuilder func bouncesOnlyWhenNeeded() -> some View {
        if #available(iOS 16.4, *) { scrollBounceBehavior(.basedOnSize) } else { self }
    }

    /// Sheets: iOS 26 draws its own glass; 16.4–18 get a see-through material.
    @ViewBuilder func sheetGlass() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else if #available(iOS 16.4, *) {
            presentationBackground(.ultraThinMaterial)
        } else {
            self
        }
    }
}

struct MaterialGlass: ViewModifier {
    let radius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background((tint ?? .clear).opacity(0.35), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05), .white.opacity(0.18)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
    }
}

struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

@MainActor func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

/// Round glass button with an SF Symbol.
struct RoundButton: View {
    let icon: String
    var size: CGFloat = 58
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button { haptic(); action() } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .glass(size / 2, tint: tint, interactive: true)
        }
        .buttonStyle(Press())
    }
}

/// Fires once on touch, then repeats while held (volume, arrows).
struct RepeatButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var pressed = false
    @State private var timer: Timer?

    var body: some View {
        label()
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    haptic()
                    action()
                    let t = Timer(fire: Date().addingTimeInterval(0.45), interval: 0.16, repeats: true) { _ in action() }
                    RunLoop.main.add(t, forMode: .common)
                    timer = t
                }
                .onEnded { _ in
                    pressed = false
                    timer?.invalidate()
                    timer = nil
                })
            .onDisappear { timer?.invalidate() }
    }
}
