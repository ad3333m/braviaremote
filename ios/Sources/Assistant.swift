import SwiftUI
import Speech
import AVFoundation

/// Turns speech into text on the iPhone; Sony's API can't stream a voice to the TV, so we send the words instead.
/// Tap to start; it stops by itself once you pause, so nothing depends on holding a finger still.
@MainActor final class Listener: ObservableObject {
    @Published var text = ""
    @Published var listening = false
    @Published var problem: String?
    var onFinished: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silence: Task<Void, Never>?
    private var gotFinal = false
    private var starting = false

    /// Ask for permission when the sheet opens, so the first tap starts listening straight away.
    func prepare() async { _ = await allowed() }

    func toggle() async {
        if listening { await finish() } else { await start() }
    }

    private func start() async {
        guard !listening, !starting else { return }
        starting = true
        defer { starting = false }
        guard await allowed() else {
            problem = "Allow Microphone and Speech Recognition for BraviaRemote in the iPhone's Settings."
            return
        }
        guard let recognizer, recognizer.isAvailable else { problem = "Speech recognition isn't available right now."; return }
        text = ""; problem = nil; gotFinal = false
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
            engine.prepare()
            try engine.start()
            self.request = request
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let words = result?.bestTranscription.formattedString
                let final = result?.isFinal == true || error != nil
                Task { @MainActor in self?.heard(words, final: final) }
            }
            listening = true
            haptic(.medium)
            stopAfterSilence(5)  // nothing said at all
        } catch {
            problem = "Couldn't start the microphone."
            stopEngine()
        }
    }

    private func heard(_ words: String?, final: Bool) {
        if let words, !words.isEmpty {
            text = words
            if listening { stopAfterSilence(1.4) }
        }
        if final {
            gotFinal = true
            if listening { Task { await finish() } }
        }
    }

    private func stopAfterSilence(_ seconds: Double) {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.finish()
        }
    }

    /// Stops listening, waits briefly for the final transcript, then hands the words on.
    func finish() async {
        guard listening else { return }
        listening = false
        silence?.cancel()
        request?.endAudio()
        stopEngine()
        for _ in 0..<10 where !gotFinal { try? await Task.sleep(nanoseconds: 100_000_000) }
        task?.cancel(); task = nil; request = nil
        haptic()
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty { onFinished?(words) }
    }

    func cancel() {
        silence?.cancel()
        guard listening else { return }
        listening = false
        request?.endAudio()
        stopEngine()
        task?.cancel()
    }

    private func stopEngine() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func allowed() async -> Bool {
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard speech == .authorized else { return false }
        return await withCheckedContinuation { c in AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) } }
    }
}

struct AssistantSheet: View {
    @EnvironmentObject private var tv: TV
    @StateObject private var listener = Listener()
    @State private var typed = ""
    @State private var pulse = false

    var body: some View {
        SheetScaffold(title: "Assistant") {
            VStack(spacing: 22) {
                Text(listener.listening ? "Listening… it sends when you stop talking." : "Tap the mic and ask, like \"Show me cat videos on YouTube\".")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text(listener.text.isEmpty ? " " : listener.text)
                    .font(.system(size: 24, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 64)

                mic

                if let problem = listener.problem {
                    Text(problem).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    TextField("Or type a request", text: $typed)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.search)
                        .onSubmit(sendTyped)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .glass(18)
                    RoundButton(icon: "arrow.up", size: 52, action: sendTyped)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            listener.onFinished = { words in Task { await tv.ask(words) } }
            Task { await listener.prepare() }
        }
        .onDisappear { listener.cancel() }
    }

    private var mic: some View {
        Button { Task { await listener.toggle() } } label: {
            ZStack {
                Circle().stroke(Color.white.opacity(listener.listening ? 0.35 : 0), lineWidth: 2)
                    .frame(width: 190, height: 190)
                    .scaleEffect(pulse ? 1.15 : 0.9)
                    .opacity(pulse ? 0 : 1)
                Image(systemName: listener.listening ? "waveform" : "mic.fill")
                    .font(.system(size: 46, weight: .medium))
                    .frame(width: 150, height: 150)
                    .glass(75, tint: listener.listening ? Color.white.opacity(0.25) : nil, interactive: true)
                    .scaleEffect(listener.listening ? 1.08 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: listener.listening)
            }
            .frame(height: 200)
            .contentShape(Circle())
        }
        .buttonStyle(Press())
        .onAppear { withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true } }
    }

    private func sendTyped() {
        let words = typed.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return }
        typed = ""
        Task { await tv.ask(words) }
    }
}
