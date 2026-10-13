import Foundation
import AVFoundation
import Speech

@MainActor
final class SpeechInput: ObservableObject {
    @Published var text = ""
    @Published var listening = false
    @Published var errorMessage: String?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if listening {stop(); return}
        Task {
            let speech = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
            let mic = await AVAudioApplication.requestRecordPermission()
            guard speech && mic else {errorMessage = "マイクと音声認識を許可してください"; return}
            start()
        }
    }
    private func start() {
        stop()
        errorMessage = nil
        guard recognizer?.isAvailable == true else {errorMessage = "音声認識を利用できません";return}
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode:.measurement, options:[.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            node.installTap(onBus: 0, bufferSize: 1024, format:format) {buffer,_ in req.append(buffer)}
            engine.prepare()
            try engine.start()
            listening = true
            task = recognizer?.recognitionTask(with:req) { [weak self] result,error in
                Task { @MainActor in
                    if let result {self?.text = result.bestTranscription.formattedString}
                    if let error {self?.errorMessage = error.localizedDescription;self?.stop()}
                }
            }
        } catch {errorMessage = error.localizedDescription;stop()}
    }
    func stop() {
        if engine.isRunning {engine.stop();engine.inputNode.removeTap(onBus:0)}
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
