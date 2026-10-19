import SwiftUI
import Speech
import AVFoundation

/// Turns speech into text on the iPhone; Sony's API can't stream a voice to the TV, so we send the words instead.
@MainActor final class Listener: ObservableObject {
    @Published var text = ""
    @Published var listening = false
    @Published var problem: String?

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var held = false

    func start() async {
        guard !listening else { return }
        held = true
        guard await allowed() else {
            problem = "Allow Microphone and Speech Recognition for BraviaRemote in the iPhone's Settings."
            return
        }
        guard held else { return }  // let go while iOS was asking for permission
        guard let recognizer, recognizer.isAvailable else { problem = "Speech recognition isn't available right now."; return }
        text = ""; problem = nil
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
                let done = error != nil || result?.isFinal == true
                Task { @MainActor in
                    if let words { self?.text = words }
                    if done { self?.stopEngine() }
                }
            }
            listening = true
            if !held { request.endAudio(); stopEngine() }
        } catch {
            problem = "Couldn't start the microphone."
            stopEngine()
        }
    }

    /// Stops listening and gives the recogniser a moment to settle on the final words.
    func finish() async -> String {
        held = false
        guard listening else { return "" }
        request?.endAudio()
        stopEngine()
        try? await Task.sleep(nanoseconds: 600_000_000)
        task?.cancel()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stopEngine() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        listening = false
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
    @State private var holding = false

    var body: some View {
        SheetScaffold(title: "Assistant") {
            VStack(spacing: 22) {
                Text(listener.listening ? "Listening…" : "Hold the mic and ask, like \"Show me cat videos on YouTube\".")
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
    }

    private var mic: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(listener.listening ? 0.35 : 0), lineWidth: 2)
                .frame(width: 190, height: 190)
                .scaleEffect(pulse ? 1.15 : 0.9)
                .opacity(pulse ? 0 : 1)
            Image(systemName: "mic.fill")
                .font(.system(size: 46, weight: .medium))
                .frame(width: 150, height: 150)
                .glass(75, tint: listener.listening ? Color.white.opacity(0.25) : nil)
                .scaleEffect(listener.listening ? 1.08 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: listener.listening)
        }
        .frame(height: 200)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !holding else { return }
                holding = true
                haptic(.medium)
                Task { await listener.start() }
            }
            .onEnded { _ in
                holding = false
                Task {
                    let words = await listener.finish()
                    haptic()
                    if !words.isEmpty { await tv.ask(words) }
                }
            })
        .onAppear { withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true } }
    }

    private func sendTyped() {
        let words = typed.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return }
        typed = ""
        Task { await tv.ask(words) }
    }
}
