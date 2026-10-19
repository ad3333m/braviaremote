import SwiftUI
import PhotosUI

/// Title + close button over a scrolling body, glass sheet background.
struct SheetScaffold<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 28, weight: .bold))
                Spacer()
                Button { haptic(); dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                        .frame(width: 36, height: 36)
                        .glass(18, interactive: true)
                }
                .buttonStyle(Press())
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 14)
            ScrollView(showsIndicators: false) {
                content().padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
        .foregroundStyle(.white)
        .presentationDragIndicator(.visible)
        .sheetGlass()
    }
}

// MARK: - inputs

struct InputsSheet: View {
    @EnvironmentObject private var tv: TV
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(title: "Inputs") {
            if tv.inputs.isEmpty {
                empty(tv.power == .on ? "Looking for inputs…" : "Turn the TV on to see its inputs.")
            } else {
                VStack(spacing: 12) {
                    ForEach(tv.inputs) { input in
                        Button {
                            haptic(.medium)
                            Task { await tv.switchTo(input) }
                            dismiss()
                        } label: { row(input) }
                        .buttonStyle(Press())
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await tv.loadInputs() }
    }

    private func row(_ input: TVInput) -> some View {
        let current = input.uri == tv.nowURI
        return HStack(spacing: 14) {
            Image(systemName: input.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(current ? Color.black : Color.white)
                .frame(width: 46, height: 46)
                .background(Color.white.opacity(current ? 0.9 : 0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(input.name).font(.system(size: 17, weight: .semibold))
                Text(input.label.isEmpty ? (input.connected ? "Connected" : "Nothing plugged in") : input.title)
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            if current {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.white)
            } else if input.connected {
                Circle().fill(Color.green).frame(width: 8, height: 8)
            }
        }
        .padding(14)
        .glass(22, tint: current ? Color.white.opacity(0.15) : nil, interactive: true)
        .opacity(input.connected || current ? 1 : 0.55)
    }
}

// MARK: - apps

struct AppsSheet: View {
    @EnvironmentObject private var tv: TV
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @AppStorage("iconSize") private var iconSize = 76.0
    @AppStorage("favorites") private var favorites = ""
    @State private var iconFor: TVApp?
    @State private var picking = false
    @State private var picked: PhotosPickerItem?

    private var shown: [TVApp] {
        search.isEmpty ? tv.apps : tv.apps.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        SheetScaffold(title: "Apps") {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
                    TextField("Search apps", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5)) }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
                .glass(18)

                if tv.apps.isEmpty {
                    empty(tv.power == .on ? "Loading apps…" : "Turn the TV on to see its apps.")
                } else if shown.isEmpty {
                    empty("No app called \"\(search)\".")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: iconSize), spacing: iconSize * 0.24)], spacing: iconSize * 0.24) {
                        ForEach(shown) { app in
                            Button {
                                haptic(.medium)
                                Task { await tv.open(app) }
                                dismiss()
                            } label: {
                                AppIconView(app: app, size: iconSize, current: app.uri == tv.nowURI)
                            }
                            .buttonStyle(Press())
                            .accessibilityLabel(app.title)
                            .contextMenu { menu(app) }
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .task { await tv.loadApps() }
        .photosPicker(isPresented: $picking, selection: $picked, matching: .images)
        .onChange(of: picked) { item in
            guard let item, let app = iconFor else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                if let data { tv.setCustomIcon(data, for: app) }
                picked = nil
            }
        }
    }

    @ViewBuilder private func menu(_ app: TVApp) -> some View {
        Text(app.title)
        let pinned = Favorites.decode(favorites).contains { $0.uri == app.uri }
        Button { favorites = Favorites.toggle(app, in: favorites) } label: {
            Label(pinned ? "Remove from Home Screen" : "Add to Home Screen", systemImage: pinned ? "pin.slash" : "pin")
        }
        Button { iconFor = app; picking = true } label: { Label("Choose Icon from Photos", systemImage: "photo") }
        if tv.hasCustomIcon(app) {
            Button(role: .destructive) { tv.setCustomIcon(nil, for: app) } label: { Label("Use Automatic Icon", systemImage: "arrow.counterclockwise") }
        }
    }
}

struct AppIconView: View {
    let app: TVApp
    var size: CGFloat = 76
    var current = false
    @EnvironmentObject private var tv: TV
    @State private var image: UIImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(white: 0.26), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                Text(String(app.title.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(current ? 0.95 : 0.12), lineWidth: current ? 3 : 1))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
        .task(id: "\(app.uri)#\(tv.iconVersion)") { image = await tv.icon(for: app) }
    }
}

// MARK: - typing into the TV's search boxes

struct KeyboardSheet: View {
    @EnvironmentObject private var tv: TV
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        SheetScaffold(title: "Type") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Select a search or text box on the TV first, then type here.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 10) {
                    TextField("Text to send", text: $text)
                        .focused($focused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .onSubmit(send)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .glass(18)
                    RoundButton(icon: "paperplane.fill", size: 52, action: send)
                }
            }
        }
        .presentationDetents([.height(240)])
        .onAppear { focused = true }
    }

    private func send() {
        guard !text.isEmpty else { return }
        let t = text
        Task { await tv.typeText(t) }
    }
}

// MARK: - settings

struct SettingsSheet: View {
    @EnvironmentObject private var tv: TV
    @AppStorage("host") private var host = ""
    @AppStorage("psk") private var psk = ""
    @AppStorage("iconSize") private var iconSize = 76.0
    @AppStorage("favorites") private var favorites = ""
    @State private var note = ""
    @State private var busy = false

    var body: some View {
        SheetScaffold(title: "Your TV") {
            VStack(alignment: .leading, spacing: 16) {
                field("TV address", "192.168.4.50", $host, .numbersAndPunctuation)
                field("Pre-Shared Key", "1234", $psk, .asciiCapable)

                HStack(spacing: 12) {
                    pill("Find my TV", "magnifyingglass", find)
                    pill("Test", "checkmark.seal.fill", test)
                }
                if busy || !note.isEmpty {
                    HStack(spacing: 10) {
                        if busy { ProgressView().tint(.white) }
                        Text(note).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                }

                homeApps

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("APP ICON SIZE").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Text("\(Int(iconSize)) pt").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.55))
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "square.grid.3x3").foregroundStyle(.white.opacity(0.6))
                        Slider(value: $iconSize, in: 56...132, step: 4).tint(.white)
                        Image(systemName: "square.grid.2x2").font(.title3).foregroundStyle(.white.opacity(0.6))
                    }
                    HStack(spacing: iconSize * 0.24) {
                        ForEach(tv.apps.prefix(previewCount)) { app in AppIconView(app: app, size: iconSize) }
                        if tv.apps.isEmpty {
                            ForEach(0..<previewCount, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                                    .frame(width: iconSize, height: iconSize)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.spring(response: 0.3), value: iconSize)
                }
                .padding(18)
                .glass(24)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Set up the TV once", systemImage: "tv").font(.headline)
                    step(1, "On the TV open Settings → Network & Internet → Home network → IP control.")
                    step(2, "Set Authentication to \"Normal and Pre-Shared Key\" and pick a key, e.g. 1234. Enter the same key above.")
                    step(3, "Turn on Settings → Network & Internet → Remote start, so BraviaRemote can turn the TV on.")
                    step(4, "Keep your iPhone on the same Wi-Fi as the TV, and allow Local Network when iOS asks.")
                }
                .padding(18)
                .glass(24)
            }
        }
        .presentationDetents([.large])
        .task { if tv.apps.isEmpty { await tv.loadApps() } }
        .onDisappear { tv.reset() }
    }

    /// Tick apps to pin them to the remote's home screen.
    private var homeApps: some View {
        let picked = Set(Favorites.decode(favorites).map(\.uri))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("HOME SCREEN APPS").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("\(picked.count) chosen").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.55))
            }
            if tv.apps.isEmpty {
                Text(tv.power == .on ? "Loading apps…" : "Connect to the TV to choose apps.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.65))
            } else {
                VStack(spacing: 2) {
                    ForEach(tv.apps) { app in
                        Button {
                            haptic()
                            favorites = Favorites.toggle(app, in: favorites)
                        } label: {
                            HStack(spacing: 12) {
                                AppIconView(app: app, size: 38)
                                Text(app.title).font(.subheadline.weight(.medium)).lineLimit(1)
                                Spacer()
                                Image(systemName: picked.contains(app.uri) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(.white.opacity(picked.contains(app.uri) ? 1 : 0.35))
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(Press())
                    }
                }
            }
        }
        .padding(18)
        .glass(24)
    }

    /// As many preview icons as fit across the sheet.
    private var previewCount: Int { max(1, min(3, Int(300 / (iconSize * 1.24)))) }

    private func field(_ label: String, _ hint: String, _ value: Binding<String>, _ keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label.uppercased()).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.55))
            TextField(hint, text: value)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .padding(.horizontal, 16).padding(.vertical, 14)
                .glass(18)
        }
    }

    private func pill(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button { haptic(); action() } label: {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .glass(20, tint: Color.white.opacity(0.12), interactive: true)
        }
        .buttonStyle(Press())
        .disabled(busy)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.caption.weight(.heavy))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.15), in: Circle())
            Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func find() {
        busy = true; note = "Searching your Wi-Fi…"
        Task {
            if let found = await TVFinder.scan() {
                host = found
                note = "Found a BRAVIA at \(found)."
            } else {
                note = "No TV found. If iOS asked about Local Network, allow it and try again, or type the address."
            }
            busy = false
        }
    }

    private func test() {
        busy = true; note = "Checking…"
        Task {
            note = await tv.test()
            busy = false
        }
    }
}

@MainActor @ViewBuilder func empty(_ text: String) -> some View {
    Text(text)
        .font(.subheadline).foregroundStyle(.white.opacity(0.65))
        .frame(maxWidth: .infinity).padding(.vertical, 40)
}
