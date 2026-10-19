import SwiftUI

/// Dark backdrop with slow-drifting colour so the glass has something to blur.
struct Backdrop: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.14), Color(red: 0.01, green: 0.01, blue: 0.04)],
                           startPoint: .top, endPoint: .bottom)
            blob(Color(red: 0.36, green: 0.30, blue: 0.95), 360, x: drift ? -110 : -40, y: drift ? -300 : -230)
            blob(Color(red: 0.00, green: 0.72, blue: 0.86), 300, x: drift ? 150 : 90, y: drift ? 20 : 110)
            blob(Color(red: 0.96, green: 0.30, blue: 0.56), 260, x: drift ? -60 : -150, y: drift ? 360 : 280)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) { drift = true } }
    }

    private func blob(_ color: Color, _ size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(color.opacity(0.5)).frame(width: size, height: size).blur(radius: 90).offset(x: x, y: y)
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
