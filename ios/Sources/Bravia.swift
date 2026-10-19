import Foundation
import Darwin
import UIKit

// MARK: - what the TV reports

struct TVInput: Identifiable, Hashable {
    let uri: String, title: String, label: String, icon: String, connected: Bool
    var id: String { uri }
    /// "PlayStation" when the input has a label, otherwise "HDMI 2".
    var name: String { label.isEmpty ? title : label }

    var symbol: String {
        let s = (icon + " " + label + " " + title).lowercased()
        if s.contains("game") || s.contains("playstation") || s.contains("switch") || s.contains("xbox") { return "gamecontroller.fill" }
        if s.contains("pc") || s.contains("computer") { return "desktopcomputer" }
        if s.contains("bluray") || s.contains("blu-ray") || s.contains("dvd") || s.contains("recording") { return "play.rectangle.fill" }
        if s.contains("avamp") || s.contains("audio") || s.contains("soundbar") || s.contains("arc") { return "hifispeaker.fill" }
        if s.contains("wifidisplay") || s.contains("mirror") || s.contains("widi") { return "airplayvideo" }
        if s.contains("composite") || s.contains("component") || s.contains("scart") { return "cable.connector" }
        return "rectangle.connected.to.line.below"
    }
}

struct TVApp: Identifiable, Hashable {
    let uri: String, title: String, icon: String
    var id: String { uri }

    /// Package names to look up on Google Play. Sony's app URIs are "com.sony.dtv.<package>.<activity class>",
    /// and the activity class usually starts again with the package's first part (com/tv/org…).
    var packages: [String] {
        let prefix = "com.sony.dtv."
        guard !uri.contains(":"), !uri.contains("/") else { return [] }
        let parts = (uri.hasPrefix(prefix) ? uri.dropFirst(prefix.count) : Substring(uri)).split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return [] }
        return (2..<parts.count).filter { parts[$0] == parts[0] }.map { parts[..<$0].joined(separator: ".") }
            + [parts.dropLast().joined(separator: ".")]
    }
}

enum Power: Equatable { case unknown, on, standby, offline, badKey }

struct BraviaError: LocalizedError {
    let code: Int, message: String
    var errorDescription: String? { message }
    static let badKey = BraviaError(code: 403, message: "The TV rejected the Pre-Shared Key.")
}

// MARK: - Sony's BRAVIA REST API (JSON-RPC over http://<tv>/sony/<service>) and IRCC remote codes

struct BraviaClient {
    let host: String, psk: String

    func call(_ service: String, _ method: String, _ params: [Any] = [], version: String = "1.0",
              timeout: TimeInterval = 4) async throws -> [Any] {
        guard let url = URL(string: "http://\(host)/sony/\(service)") else { throw BraviaError(code: -1, message: "That TV address isn't valid.") }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(psk, forHTTPHeaderField: "X-Auth-PSK")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["method": method, "id": 1, "params": params, "version": version])
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 401 || status == 403 { throw BraviaError.badKey }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw BraviaError(code: status, message: "The TV sent back something unexpected (\(status)).")
        }
        if let err = json["error"] as? [Any] {
            let code = err.first as? Int ?? -1
            switch code {
            case 401, 403: throw BraviaError.badKey
            case 40005: throw BraviaError(code: code, message: "The TV is off.")
            default: throw BraviaError(code: code, message: err.dropFirst().first as? String ?? "The TV said no (\(code)).")
            }
        }
        return json["result"] as? [Any] ?? []
    }

    func sendIRCC(_ code: String) async throws {
        guard let url = URL(string: "http://\(host)/sony/ircc") else { return }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("\"urn:schemas-sony-com:service:IRCC:1#X_SendIRCC\"", forHTTPHeaderField: "SOAPACTION")
        req.setValue(psk, forHTTPHeaderField: "X-Auth-PSK")
        req.httpBody = Data(("<?xml version=\"1.0\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" "
            + "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body><u:X_SendIRCC "
            + "xmlns:u=\"urn:schemas-sony-com:service:IRCC:1\"><IRCCCode>\(code)</IRCCCode></u:X_SendIRCC></s:Body></s:Envelope>").utf8)
        let (_, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 401 || status == 403 { throw BraviaError.badKey }
    }
}

enum Key: String {
    case up = "Up", down = "Down", left = "Left", right = "Right", ok = "Confirm", back = "Return", home = "Home",
         options = "Options", play = "Play", pause = "Pause", rewind = "Rewind", forward = "Forward",
         volumeUp = "VolumeUp", volumeDown = "VolumeDown", mute = "Mute"

    /// Sony's standard codes; the TV's own list (getRemoteControllerInfo) replaces these once it's read.
    static let defaults: [String: String] = [
        "Up": "AAAAAQAAAAEAAAB0Aw==", "Down": "AAAAAQAAAAEAAAB1Aw==", "Left": "AAAAAQAAAAEAAAA0Aw==",
        "Right": "AAAAAQAAAAEAAAAzAw==", "Confirm": "AAAAAQAAAAEAAABlAw==", "Return": "AAAAAgAAAJcAAAAjAw==",
        "Home": "AAAAAQAAAAEAAABgAw==", "Options": "AAAAAgAAAJcAAAA2Aw==", "Play": "AAAAAgAAAJcAAAAaAw==",
        "Pause": "AAAAAgAAAJcAAAAZAw==", "Rewind": "AAAAAgAAAJcAAAAbAw==", "Forward": "AAAAAgAAAJcAAAAcAw==",
        "VolumeUp": "AAAAAQAAAAEAAAASAw==", "VolumeDown": "AAAAAQAAAAEAAAATAw==", "Mute": "AAAAAQAAAAEAAAAUAw==",
    ]
}

// MARK: - the TV, as the UI sees it

@MainActor final class TV: ObservableObject {
    @Published var power = Power.unknown
    @Published var model = ""
    @Published var nowURI = ""
    @Published var nowPlaying = ""
    @Published var inputs: [TVInput] = []
    @Published var apps: [TVApp] = []
    @Published var volume: Int?
    @Published var muted = false
    @Published var toast: String?

    let demo = UserDefaults.standard.bool(forKey: "demo")
    private var codes = Key.defaults
    private var codesLoaded = false
    private let icons = NSCache<NSString, UIImage>()

    var host: String { (UserDefaults.standard.string(forKey: "host") ?? "").trimmingCharacters(in: .whitespaces) }
    private var psk: String { UserDefaults.standard.string(forKey: "psk") ?? "" }
    private var client: BraviaClient { BraviaClient(host: host, psk: psk) }

    init() { if demo { fillDemo() } }

    /// Called after the address or key changes.
    func reset() {
        guard !demo else { return }
        model = ""; inputs = []; apps = []; nowURI = ""; nowPlaying = ""; volume = nil; codesLoaded = false
        power = .unknown
    }

    func refresh() async {
        guard !demo, !host.isEmpty else { return }
        do {
            let r = try await client.call("system", "getPowerStatus", timeout: 2.5)
            power = (r.first as? [String: Any])?["status"] as? String == "active" ? .on : .standby
        } catch let e as BraviaError where e.code == 403 {
            power = .badKey; return
        } catch {
            power = .offline; return
        }
        guard power == .on else { return }

        do {
            let r = try await client.call("audio", "getVolumeInformation")
            if let list = r.first as? [[String: Any]], let out = list.first(where: { $0["target"] as? String == "speaker" }) ?? list.first {
                volume = out["volume"] as? Int
                muted = out["mute"] as? Bool ?? false
            }
        } catch let e as BraviaError where e.code == 403 {
            power = .badKey; return
        } catch {}

        if model.isEmpty, let info = (try? await client.call("system", "getSystemInformation"))?.first as? [String: Any] {
            model = info["model"] as? String ?? ""
            if let mac = info["macAddr"] as? String, !mac.isEmpty { UserDefaults.standard.set(mac, forKey: "mac") }
        }
        if !codesLoaded, let r = try? await client.call("system", "getRemoteControllerInfo"), r.count > 1,
           let list = r[1] as? [[String: Any]] {
            for item in list { if let n = item["name"] as? String, let v = item["value"] as? String { codes[n] = v } }
            codesLoaded = true
        }
        if inputs.isEmpty { await loadInputs() }
        await loadNowPlaying()
    }

    private func loadNowPlaying() async {
        // Fails with "Illegal State" while an app is in front, so keep the app name we set when opening it.
        guard let info = (try? await client.call("avContent", "getPlayingContentInfo"))?.first as? [String: Any],
              let uri = info["uri"] as? String else {
            if nowURI.hasPrefix("extInput") { nowURI = ""; nowPlaying = "" }
            return
        }
        nowURI = uri
        nowPlaying = inputs.first(where: { $0.uri == uri })?.name ?? info["title"] as? String ?? ""
    }

    func loadInputs() async {
        guard !demo, !host.isEmpty else { return }
        var r = try? await client.call("avContent", "getCurrentExternalInputsStatus", version: "1.1")
        if r == nil { r = try? await client.call("avContent", "getCurrentExternalInputsStatus") }
        guard let list = r?.first as? [[String: Any]] else { return }
        inputs = list.compactMap { d -> TVInput? in
            guard let uri = d["uri"] as? String else { return nil }
            return TVInput(uri: uri, title: d["title"] as? String ?? uri, label: d["label"] as? String ?? "",
                           icon: d["icon"] as? String ?? "", connected: d["connection"] as? Bool ?? true)
        }
    }

    func loadApps() async {
        guard !demo, !host.isEmpty, let r = try? await client.call("appControl", "getApplicationList"),
              let list = r.first as? [[String: Any]] else { return }
        apps = list.compactMap { d -> TVApp? in
            guard let uri = d["uri"] as? String, let title = d["title"] as? String else { return nil }
            return TVApp(uri: uri, title: title, icon: d["icon"] as? String ?? "")
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: actions

    func switchTo(_ input: TVInput) async {
        await ensureOn()
        if await run("Switched to \(input.name)", { try await $0.call("avContent", "setPlayContent", [["uri": input.uri]]) }) {
            nowURI = input.uri; nowPlaying = input.name
        }
    }

    func open(_ app: TVApp) async {
        await ensureOn()
        if await run("Opening \(app.title)", { try await $0.call("appControl", "setActiveApp", [["uri": app.uri]]) }) {
            nowURI = app.uri; nowPlaying = app.title
        }
    }

    func send(_ key: Key) {
        guard let code = codes[key.rawValue] else { return }
        Task {
            await run { try await $0.sendIRCC(code) }
            if key == .volumeUp || key == .volumeDown || key == .mute { await refreshVolume() }
        }
    }

    /// Opens Google search / Assistant on the TV, then types the request into it.
    func ask(_ words: String) async {
        if demo { show("Asked: \(words)"); return }
        await ensureOn()
        if apps.isEmpty { await loadApps() }
        let assistant = apps.first { app in
            app.uri.contains("katniss") || ["assistant", "google search"].contains { app.title.lowercased().contains($0) }
        }
        if let assistant {
            _ = try? await client.call("appControl", "setActiveApp", [["uri": assistant.uri]])
        } else if let key = codes.keys.first(where: { name in ["assist", "search", "voice"].contains { name.lowercased().contains($0) } }),
                  let code = codes[key] {
            try? await client.sendIRCC(code)
        }
        // The search box takes a moment to appear (longer when the app is cold), so keep offering the text until it's taken.
        for attempt in 0..<10 {
            try? await Task.sleep(nanoseconds: attempt == 0 ? 900_000_000 : 600_000_000)
            if (try? await client.call("appControl", "setTextForm", [words])) != nil {
                show("Asked: \(words)")
                return
            }
        }
        show("The TV didn't open a search box. Try again, or use Type.")
    }

    func typeText(_ text: String) async {
        await run("Sent to the TV") { try await $0.call("appControl", "setTextForm", [text]) }
    }

    func togglePower() async {
        if power == .on {
            if await run(nil, { try await $0.call("system", "setPowerStatus", [["status": false]]) }) { power = .standby }
        } else {
            await turnOn()
        }
    }

    private func ensureOn() async {
        guard power != .on, !demo else { return }
        await turnOn()
        try? await Task.sleep(nanoseconds: 1_500_000_000)
    }

    private func turnOn() async {
        if demo { power = .on; return }
        show("Turning on…")
        if let mac = parseMAC(UserDefaults.standard.string(forKey: "mac") ?? "") { _ = WakeOnLAN.send(mac: mac, host: host) }
        _ = try? await client.call("system", "setPowerStatus", [["status": true]])
        for _ in 0..<10 {
            await refresh()
            if power == .on || power == .badKey { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        if power != .on && power != .badKey {
            show("No answer. Turn on Remote start on the TV so it can be woken.")
        }
    }

    private func refreshVolume() async {
        guard let list = (try? await client.call("audio", "getVolumeInformation"))?.first as? [[String: Any]],
              let out = list.first(where: { $0["target"] as? String == "speaker" }) ?? list.first else { return }
        volume = out["volume"] as? Int
        muted = out["mute"] as? Bool ?? false
    }

    /// Checks the address and key, for the settings screen.
    func test() async -> String {
        guard !host.isEmpty else { return "Enter the TV's address first." }
        do {
            let r = try await client.call("system", "getSystemInformation")
            let info = r.first as? [String: Any] ?? [:]
            reset()
            await refresh()
            return "Connected to \(info["model"] as? String ?? "your BRAVIA")."
        } catch {
            return describe(error)
        }
    }

    @discardableResult
    private func run(_ success: String? = nil, _ work: (BraviaClient) async throws -> Void) async -> Bool {
        if demo { if let success { show(success) }; return true }
        do {
            try await work(client)
            if let success { show(success) }
            return true
        } catch {
            if (error as? BraviaError)?.code == 403 { power = .badKey }
            show(describe(error))
            return false
        }
    }

    private func describe(_ error: Error) -> String {
        if let e = error as? BraviaError { return e.message }
        if error is URLError { return "Can't reach the TV. Is your iPhone on the same Wi-Fi?" }
        return error.localizedDescription
    }

    func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == message { toast = nil }
        }
    }

    /// Sideloaded apps that aren't on Google Play but have an icon online.
    private static let ownIcons = [
        "com.ad3333m.ciname": "https://raw.githubusercontent.com/ad3333m/anikku/main/ciname/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
    ]

    /// Icon order: one you picked from Photos, a known one, Google Play, the TV's own, APKPure (sideloaded apps),
    /// else nil for a letter tile.
    func icon(for app: TVApp) async -> UIImage? {
        if let hit = icons.object(forKey: app.uri as NSString) { return hit }
        var image = UIImage(contentsOfFile: customIconFile(app).path)
        if image == nil, let own = app.packages.lazy.compactMap({ Self.ownIcons[$0] }).first, let url = URL(string: own) {
            image = await fetchImage(url)
        }
        for package in app.packages where image == nil {
            if let url = await storeIcon(package, store: "playIcons",
                                         page: "https://play.google.com/store/apps/details?id=\(package)&hl=en",
                                         parse: Self.playIcon) {
                image = await fetchImage(url)
            }
        }
        if image == nil, var parts = URLComponents(string: app.icon), parts.scheme != nil {
            if parts.host == "localhost" || parts.host == "127.0.0.1" { parts.host = host }
            if let url = parts.url { image = await fetchImage(url, key: true) }
        }
        for package in app.packages where image == nil {
            if let url = await storeIcon(package, store: "apkpureIcons", page: "https://apkpure.com/search?q=\(package)",
                                         parse: { Self.apkpureIcon($0, package) }) {
                image = await fetchImage(url)
            }
        }
        if let image { icons.setObject(image, forKey: app.uri as NSString) }
        return image
    }

    /// Looks the package up on a store page once and remembers the icon address ("" = not there).
    private func storeIcon(_ package: String, store: String, page: String, parse: (String) -> String?) async -> URL? {
        if let known = (UserDefaults.standard.dictionary(forKey: store) as? [String: String])?[package] {
            return URL(string: known)
        }
        guard let url = URL(string: page) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        guard let res = try? await URLSession.shared.data(for: req) else { return nil }
        let status = (res.1 as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 404 else { return nil }  // network trouble: try again next time
        let found = status == 200 ? String(data: res.0, encoding: .utf8).flatMap(parse) ?? "" : ""
        var known = UserDefaults.standard.dictionary(forKey: store) as? [String: String] ?? [:]
        known[package] = found
        UserDefaults.standard.set(known, forKey: store)
        return URL(string: found)
    }

    /// Google Play: og:image is the icon; "=s256" asks for a 256px copy.
    private static func playIcon(_ html: String) -> String? {
        guard let start = html.range(of: "<meta property=\"og:image\" content=\""),
              let end = html[start.upperBound...].firstIndex(of: "\"") else { return nil }
        let full = html[start.upperBound..<end]
        return String(full.split(separator: "=", maxSplits: 1).first ?? full) + "=s256"
    }

    /// APKPure search: the result linking to ".../<package>" has its icon in the next <img>.
    private static func apkpureIcon(_ html: String, _ package: String) -> String? {
        guard let link = html.range(of: "/\(package)\""),
              let img = html.range(of: "<img", range: link.upperBound..<(html.index(link.upperBound, offsetBy: 800, limitedBy: html.endIndex) ?? html.endIndex)),
              let src = html.range(of: " src=\"", range: img.upperBound..<html.endIndex),
              let end = html[src.upperBound...].firstIndex(of: "\"") else { return nil }
        let url = html[src.upperBound..<end].replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "w=160", with: "w=256")
        return url.hasPrefix("https://") ? url : nil
    }

    // MARK: icons you choose yourself

    @Published var iconVersion = 0

    private func customIconFile(_ app: TVApp) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = String(String(app.uri.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }).suffix(120))
        return dir.appendingPathComponent(name + ".png")
    }

    func hasCustomIcon(_ app: TVApp) -> Bool { FileManager.default.fileExists(atPath: customIconFile(app).path) }

    /// Saves a picture (cropped square, 256pt) as the app's icon; nil goes back to the automatic one.
    func setCustomIcon(_ data: Data?, for app: TVApp) {
        let file = customIconFile(app)
        if let data, let picture = UIImage(data: data) {
            let side: CGFloat = 256
            let scale = max(side / picture.size.width, side / picture.size.height)
            let size = CGSize(width: picture.size.width * scale, height: picture.size.height * scale)
            let png = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).pngData { _ in
                picture.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
            }
            try? png.write(to: file)
        } else {
            try? FileManager.default.removeItem(at: file)
        }
        icons.removeObject(forKey: app.uri as NSString)
        iconVersion += 1
    }

    private func fetchImage(_ url: URL, key: Bool = false) async -> UIImage? {
        var req = URLRequest(url: url, timeoutInterval: 10)
        if key { req.setValue(psk, forHTTPHeaderField: "X-Auth-PSK") }
        guard let res = try? await URLSession.shared.data(for: req) else { return nil }
        return UIImage(data: res.0)
    }

    private func fillDemo() {
        power = .on; model = "K-77XR80"; volume = 18
        inputs = [
            TVInput(uri: "extInput:hdmi?port=1", title: "HDMI 1", label: "PC", icon: "meta:pc", connected: true),
            TVInput(uri: "extInput:hdmi?port=2", title: "HDMI 2", label: "Nintendo Switch", icon: "meta:game", connected: true),
            TVInput(uri: "extInput:hdmi?port=3", title: "HDMI 3", label: "", icon: "meta:hdmi", connected: false),
            TVInput(uri: "extInput:hdmi?port=4", title: "HDMI 4 (eARC/ARC)", label: "Soundbar", icon: "meta:avamp", connected: true),
            TVInput(uri: "extInput:widi?port=1", title: "Screen mirroring", label: "", icon: "meta:wifidisplay", connected: true),
        ]
        apps = [
            ("YouTube", "com.google.android.youtube.tv.com.google.android.apps.youtube.tv.activity.ShellActivity"),
            ("Netflix", "com.netflix.ninja.com.netflix.ninja.MainActivity"),
            ("Prime Video", "com.amazon.amazonvideo.livingroom.com.amazon.ignition.IgnitionActivity"),
            ("Disney+", "com.disney.disneyplus.com.bamtechmedia.dominguez.main.MainActivity"),
            ("Spotify", "com.spotify.tv.android.com.spotify.tv.android.SpotifyTVActivity"),
            ("Twitch", "tv.twitch.android.viewer.tv.twitch.android.apps.TwitchActivity"),
            ("Plex", "com.plexapp.android.com.plexapp.plex.activities.SplashActivity"),
            ("Crunchyroll", "com.crunchyroll.crunchyroid.com.ellation.crunchyroll.presentation.startup.StartupActivity"),
            ("Apple TV", "com.apple.atve.androidtv.appletv.com.apple.atve.androidtv.appletv.MainActivity"),
            ("Google Play Store", "com.android.vending.com.google.android.finsky.tvmainactivity.TvMainActivity"),
            ("Ciname TV", "com.ad3333m.ciname.com.ad3333m.ciname.MainActivity"),
            ("Live TV", "com.sony.dtv.tvx.com.sony.dtv.tvx.MainActivity"),
            ("SmartTube", "com.liskovsoft.smarttubetv.beta.com.liskovsoft.smartyoutubetv2.tv.ui.main.SplashActivity"),
        ]
        .map { TVApp(uri: "com.sony.dtv." + $0.1, title: $0.0, icon: "") }
        .sorted { $0.title < $1.title }
        nowURI = "extInput:hdmi?port=2"; nowPlaying = "Nintendo Switch"
        if Favorites.decode(UserDefaults.standard.string(forKey: "favorites") ?? "").isEmpty {
            let picks = apps.filter { ["YouTube", "Netflix", "Ciname TV", "Spotify", "Disney+"].contains($0.title) }
            UserDefaults.standard.set(Favorites.encode(picks), forKey: "favorites")
        }
    }
}

// MARK: - favourite apps for the remote's home screen, kept as "uri<TAB>title<TAB>icon" lines

enum Favorites {
    static func decode(_ raw: String) -> [TVApp] {
        raw.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            return f.count >= 2 ? TVApp(uri: f[0], title: f[1], icon: f.count > 2 ? f[2] : "") : nil
        }
    }

    static func encode(_ apps: [TVApp]) -> String {
        apps.map { "\($0.uri)\t\($0.title)\t\($0.icon)" }.joined(separator: "\n")
    }

    static func toggle(_ app: TVApp, in raw: String) -> String {
        var list = decode(raw)
        if let i = list.firstIndex(where: { $0.uri == app.uri }) { list.remove(at: i) } else { list.append(app) }
        return encode(list)
    }
}

// MARK: - finding the TV on the Wi-Fi

enum TVFinder {
    /// Asks every address on the iPhone's Wi-Fi subnet for getInterfaceInformation (no key needed), own /24 first.
    static func scan() async -> String? {
        guard let addr = wifiAddress() else { return nil }
        let (ip, mask) = addr
        let net = ip & mask
        let count = min(~mask, 1023)  // ponytail: covers up to a /22 (his network); bigger subnets only get their first 1022 hosts
        let all = (1..<count).map { net | $0 }.filter { $0 != ip }
        let sameBlock = all.filter { $0 & 0xFFFF_FF00 == ip & 0xFFFF_FF00 }
        let ordered = sameBlock + all.filter { $0 & 0xFFFF_FF00 != ip & 0xFFFF_FF00 }

        for start in stride(from: 0, to: ordered.count, by: 64) {
            let batch = ordered[start..<min(start + 64, ordered.count)].map(dotted)
            let found = await withTaskGroup(of: String?.self) { group -> String? in
                for host in batch { group.addTask { await isBravia(host) ? host : nil } }
                for await hit in group { if let hit { group.cancelAll(); return hit } }
                return nil
            }
            if let found { return found }
        }
        return nil
    }

    private static func isBravia(_ host: String) async -> Bool {
        guard let r = try? await BraviaClient(host: host, psk: "").call("system", "getInterfaceInformation", timeout: 1.5),
              let info = r.first as? [String: Any] else { return false }
        return info["productCategory"] as? String == "tv" || (info["productName"] as? String ?? "").contains("BRAVIA")
    }

    private static func dotted(_ a: UInt32) -> String { "\(a >> 24 & 255).\(a >> 16 & 255).\(a >> 8 & 255).\(a & 255)" }

    private static func wifiAddress() -> (UInt32, UInt32)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard String(cString: ifa.ifa_name) == "en0", let addr = ifa.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  let mask = ifa.ifa_netmask else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let m = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            return (ip, m)
        }
        return nil
    }
}

// MARK: - Wake-on-LAN (from PowerSwitch), a second way to wake the TV next to setPowerStatus

func parseMAC(_ text: String) -> [UInt8]? {
    let hex = text.filter(\.isHexDigit)
    guard hex.count == 12 else { return nil }
    return stride(from: 0, to: 12, by: 2).compactMap { i in
        UInt8(hex[hex.index(hex.startIndex, offsetBy: i)..<hex.index(hex.startIndex, offsetBy: i + 2)], radix: 16)
    }
}

enum WakeOnLAN {
    /// Magic packet to UDP 9, sent straight to the TV (iOS blocks broadcasts without Apple's multicast entitlement).
    static func send(mac: [UInt8], host: String) -> Bool {
        let packet = [UInt8](repeating: 0xFF, count: 6) + Array([[UInt8]](repeating: mac, count: 16).joined())
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(9).bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }
        var sent = false
        for _ in 0..<3 {
            let n = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if n == packet.count { sent = true }
        }
        return sent
    }
}
