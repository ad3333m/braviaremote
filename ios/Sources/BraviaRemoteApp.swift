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
    case inputs, apps, keyboard, assistant, settings
    var id: String { rawValue }
}

struct RemoteView: View {
    @EnvironmentObject private var tv: TV
    @State private var panel: Panel?
    @AppStorage("favorites") private var favorites = ""
    @AppStorage("tvName") private var tvName = ""
    @AppStorage("model") private var savedModel = ""
    @Environment(\.scenePhase) private var phase
    private let poll = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Backdrop()
            // Everything fits on one screen: the d-pad takes whatever height is left (small phones still scroll).
            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                        problem
                        sources
                        favoritesRow
                        Spacer(minLength: 0)
                        dpad(dpadSize(geo.size.height))
                        Spacer(minLength: 0)
                        navRow
                        HStack(spacing: 14) { media; volume }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                    .frame(minHeight: geo.size.height)
                }
                .bouncesOnlyWhenNeeded()
            }
            toast
        }
        .foregroundStyle(.white)
        .sheet(item: $panel, onDismiss: { Task { await tv.refresh() } }) { p in
            switch p {
            case .inputs: InputsSheet()
            case .apps: AppsSheet()
            case .keyboard: KeyboardSheet()
            case .assistant: AssistantSheet()
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
                Text(title).font(.system(size: 26, weight: .semibold)).tracking(title.count > 10 ? 1 : 4)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 7) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                        .shadow(color: statusColor, radius: 4)
                    Text(statusText).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
            }
            Spacer()
            RoundButton(icon: "gearshape.fill", size: 46) { panel = .settings }
            RoundButton(icon: "power", size: 58, tint: tv.power == .on ? Color(red: 1, green: 0.3, blue: 0.3).opacity(0.45) : nil) {
                Task { await tv.togglePower() }
            }
        }
    }

    /// Your name for the TV, else its series worked out from the model ("K-77XR80" is a BRAVIA 8).
    private var title: String {
        let custom = tvName.trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? braviaSeries(tv.model.isEmpty ? savedModel : tv.model) : custom
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
                .glass(22, interactive: true)
            }
            .buttonStyle(Press())
        }
    }

    // MARK: inputs + apps

    private var sources: some View {
        let onInput = tv.nowURI.hasPrefix("extInput")
        let onApp = !onInput && !tv.nowPlaying.isEmpty
        return HStack(spacing: 14) {
            tile("Inputs", icon: "tv.and.mediabox", detail: onInput ? tv.nowPlaying : "HDMI & more") { panel = .inputs }
            tile("Apps", icon: "square.grid.2x2", detail: onApp ? tv.nowPlaying : "Open any app") { panel = .apps }
        }
    }

    private func tile(_ title: String, icon: String, detail: String, action: @escaping () -> Void) -> some View {
        Button { haptic(.medium); action() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    Text(detail).font(.footnote.weight(.medium)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .glass(24, interactive: true)
        }
        .buttonStyle(Press())
    }

    // MARK: favourite apps (picked in settings)

    @ViewBuilder private var favoritesRow: some View {
        let apps = Favorites.decode(favorites)
        if !apps.isEmpty {
            // Centred when they fit, scrolling when there are too many.
            ViewThatFits(in: .horizontal) {
                favoriteIcons(apps).padding(14).frame(maxWidth: .infinity)
                ScrollView(.horizontal, showsIndicators: false) { favoriteIcons(apps).padding(14) }
            }
            .glass(26)
        }
    }

    private func favoriteIcons(_ apps: [TVApp]) -> some View {
        HStack(spacing: 14) {
            ForEach(apps) { app in
                Button {
                    haptic(.medium)
                    Task { await tv.open(app) }
                } label: {
                    AppIconView(app: app, size: 58, current: app.uri == tv.nowURI)
                }
                .buttonStyle(Press())
                .accessibilityLabel(app.title)
            }
        }
    }

    // MARK: d-pad

    /// Height left for the d-pad once the fixed rows are placed (rows + 16pt gaps + padding), 170–262pt.
    private func dpadSize(_ height: CGFloat) -> CGFloat {
        var fixed: CGFloat = 14 + 58 + 74 + 76 + 104 + 16 * 7
        if !Favorites.decode(favorites).isEmpty { fixed += 86 + 16 }
        if tv.power == .offline || tv.power == .badKey { fixed += 80 + 16 }
        return min(262, max(170, height - fixed))
    }

    private func dpad(_ size: CGFloat) -> some View {
        let ok = size * 0.37
        let arrowSide = (size - ok) / 2
        return ZStack {
            Circle().fill(Color.white.opacity(0.001)).frame(width: size, height: size).glass(size / 2)
            VStack(spacing: 0) {
                arrow("chevron.up", .up, arrowSide)
                HStack(spacing: 0) {
                    arrow("chevron.left", .left, arrowSide)
                    Button { haptic(.medium); tv.send(.ok) } label: {
                        Text("OK")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: ok, height: ok)
                            .glass(ok / 2, tint: .white.opacity(0.12), interactive: true)
                    }
                    .buttonStyle(Press())
                    arrow("chevron.right", .right, arrowSide)
                }
                arrow("chevron.down", .down, arrowSide)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func arrow(_ icon: String, _ key: Key, _ side: CGFloat) -> some View {
        RepeatButton(action: { tv.send(key) }) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: side, height: side)
        }
    }

    // MARK: back / home / options / keyboard

    private var navRow: some View {
        HStack {
            labelled("Back") { RoundButton(icon: "arrow.uturn.backward", size: 54) { tv.send(.back) } }
            Spacer(minLength: 4)
            labelled("Home") { RoundButton(icon: "house.fill", size: 54) { tv.send(.home) } }
            Spacer(minLength: 4)
            labelled("Assistant") { RoundButton(icon: "mic.fill", size: 54) { panel = .assistant } }
            Spacer(minLength: 4)
            labelled("Options") { RoundButton(icon: "ellipsis", size: 54) { tv.send(.options) } }
            Spacer(minLength: 4)
            labelled("Type") { RoundButton(icon: "keyboard", size: 54) { panel = .keyboard } }
        }
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
                .frame(maxWidth: .infinity).frame(height: 51).contentShape(Rectangle())
        }
        .buttonStyle(Press())
    }

    private var volume: some View {
        HStack(spacing: 0) {
            RepeatButton(action: { tv.send(.volumeDown) }) {
                Image(systemName: "minus").font(.system(size: 20, weight: .bold)).frame(width: 50, height: 104)
            }
            Button { haptic(.medium); tv.send(.mute) } label: {
                VStack(spacing: 6) {
                    Image(systemName: tv.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tv.muted ? Color.orange : Color.white)
                    Text(tv.volume.map { "\($0)" } ?? "–")
                        .font(.system(size: 26, weight: .semibold)).monospacedDigit()
                    Text("VOLUME").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(Press())
            RepeatButton(action: { tv.send(.volumeUp) }) {
                Image(systemName: "plus").font(.system(size: 20, weight: .bold)).frame(width: 50, height: 104)
            }
        }
        .frame(height: 104)
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
