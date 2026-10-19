import SwiftUI

@main
struct BraviaRemoteApp: App {
    @StateObject private var tv = TV()

    var body: some Scene {
        WindowGroup {
            RemoteView().environmentObject(tv).preferredColorScheme(.dark)
        }
    }
}

enum Panel: String, Identifiable {
    case inputs, apps, keyboard, settings
    var id: String { rawValue }
}

struct RemoteView: View {
    @EnvironmentObject private var tv: TV
    @State private var panel: Panel?
    @Environment(\.scenePhase) private var phase
    private let poll = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header
                    problem
                    sources
                    dpad
                    navRow
                    HStack(spacing: 14) { media; volume }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
            toast
        }
        .foregroundStyle(.white)
        .sheet(item: $panel, onDismiss: { Task { await tv.refresh() } }) { p in
            switch p {
            case .inputs: InputsSheet()
            case .apps: AppsSheet()
            case .keyboard: KeyboardSheet()
            case .settings: SettingsSheet()
            }
        }
        .onAppear {
            if let start = UserDefaults.standard.string(forKey: "sheet").flatMap(Panel.init(rawValue:)) { panel = start }
            else if tv.host.isEmpty && !tv.demo { panel = .settings }
            Task { await tv.refresh() }
        }
        .onReceive(poll) { _ in
            if phase == .active && panel == nil { Task { await tv.refresh() } }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("BRAVIA").font(.system(size: 30, weight: .heavy, design: .rounded)).tracking(1.5)
                HStack(spacing: 7) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                        .shadow(color: statusColor, radius: 4)
                    Text(statusText).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
            }
            Spacer()
            RoundButton(icon: "gearshape.fill", size: 46) { panel = .settings }
            RoundButton(icon: "power", size: 58, tint: tv.power == .on ? Color(red: 1, green: 0.25, blue: 0.3) : .green) {
                Task { await tv.togglePower() }
            }
        }
    }

    private var statusText: String {
        switch tv.power {
        case .on: return [tv.model, "On"].filter { !$0.isEmpty }.joined(separator: " · ")
        case .standby: return "Standby"
        case .offline: return "Not reachable"
        case .badKey: return "Wrong Pre-Shared Key"
        case .unknown: return tv.host.isEmpty ? "Not set up" : "Connecting…"
        }
    }

    private var statusColor: Color {
        switch tv.power {
        case .on: return .green
        case .standby: return .orange
        case .offline, .badKey: return .red
        case .unknown: return .gray
        }
    }

    @ViewBuilder private var problem: some View {
        if tv.power == .offline || tv.power == .badKey {
            Button { haptic(); panel = .settings } label: {
                HStack(spacing: 14) {
                    Image(systemName: tv.power == .badKey ? "key.fill" : "wifi.exclamationmark")
                        .font(.title2).foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tv.power == .badKey ? "The TV rejected the key" : "Can't reach your TV").font(.headline)
                        Text(tv.power == .badKey ? "Check the Pre-Shared Key in settings."
                                                 : "Check the address and that your iPhone is on the same Wi-Fi.")
                            .font(.footnote).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.5))
                }
                .padding(16)
                .glass(22, tint: .orange.opacity(0.25), interactive: true)
            }
            .buttonStyle(Press())
        }
    }

    // MARK: inputs + apps

    private var sources: some View {
        let onInput = tv.nowURI.hasPrefix("extInput")
        let onApp = !onInput && !tv.nowPlaying.isEmpty
        return HStack(spacing: 14) {
            tile("Inputs", icon: "rectangle.connected.to.line.below", tint: Color(red: 0.1, green: 0.75, blue: 0.95),
                 detail: onInput ? tv.nowPlaying : "HDMI & more") { panel = .inputs }
            tile("Apps", icon: "square.grid.2x2.fill", tint: Color(red: 0.65, green: 0.45, blue: 1),
                 detail: onApp ? tv.nowPlaying : "Open any app") { panel = .apps }
        }
    }

    private func tile(_ title: String, icon: String, tint: Color, detail: String, action: @escaping () -> Void) -> some View {
        Button { haptic(.medium); action() } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.85), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: tint.opacity(0.6), radius: 10, y: 4)
                Spacer(minLength: 14)
                Text(title).font(.system(size: 20, weight: .bold, design: .rounded))
                Text(detail).font(.footnote.weight(.medium)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 128)
            .padding(16)
            .glass(26, interactive: true)
        }
        .buttonStyle(Press())
    }

    // MARK: d-pad

    private var dpad: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.001)).frame(width: 262, height: 262).glass(131)
            VStack(spacing: 0) {
                arrow("chevron.up", .up)
                HStack(spacing: 0) {
                    arrow("chevron.left", .left)
                    Button { haptic(.medium); tv.send(.ok) } label: {
                        Text("OK")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .frame(width: 96, height: 96)
                            .glass(48, tint: .white.opacity(0.12), interactive: true)
                    }
                    .buttonStyle(Press())
                    arrow("chevron.right", .right)
                }
                arrow("chevron.down", .down)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func arrow(_ icon: String, _ key: Key) -> some View {
        RepeatButton(action: { tv.send(key) }) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 80, height: 80)
        }
    }

    // MARK: back / home / options / keyboard

    private var navRow: some View {
        HStack {
            labelled("Back") { RoundButton(icon: "arrow.uturn.backward") { tv.send(.back) } }
            Spacer()
            labelled("Home") { RoundButton(icon: "house.fill") { tv.send(.home) } }
            Spacer()
            labelled("Options") { RoundButton(icon: "ellipsis") { tv.send(.options) } }
            Spacer()
            labelled("Type") { RoundButton(icon: "keyboard") { panel = .keyboard } }
        }
        .padding(.horizontal, 6)
    }

    private func labelled<B: View>(_ text: String, @ViewBuilder _ button: () -> B) -> some View {
        VStack(spacing: 7) {
            button()
            Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: media + volume

    private var media: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                mediaKey("backward.fill", .rewind)
                mediaKey("forward.fill", .forward)
            }
            Divider().overlay(Color.white.opacity(0.15))
            HStack(spacing: 0) {
                mediaKey("play.fill", .play)
                mediaKey("pause.fill", .pause)
            }
        }
        .glass(26)
    }

    private func mediaKey(_ icon: String, _ key: Key) -> some View {
        Button { haptic(); tv.send(key) } label: {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 62).contentShape(Rectangle())
        }
        .buttonStyle(Press())
    }

    private var volume: some View {
        HStack(spacing: 0) {
            RepeatButton(action: { tv.send(.volumeDown) }) {
                Image(systemName: "minus").font(.system(size: 20, weight: .bold)).frame(width: 50, height: 124)
            }
            Button { haptic(.medium); tv.send(.mute) } label: {
                VStack(spacing: 6) {
                    Image(systemName: tv.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tv.muted ? Color.orange : Color.white)
                    Text(tv.volume.map { "\($0)" } ?? "–")
                        .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("VOLUME").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(Press())
            RepeatButton(action: { tv.send(.volumeUp) }) {
                Image(systemName: "plus").font(.system(size: 20, weight: .bold)).frame(width: 50, height: 124)
            }
        }
        .frame(height: 124)
        .glass(26)
    }

    // MARK: toast

    private var toast: some View {
        VStack {
            Spacer()
            if let message = tv.toast {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20).padding(.vertical, 13)
                    .glass(22)
                    .padding(.horizontal, 24).padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: tv.toast)
        .allowsHitTesting(false)
    }
}
