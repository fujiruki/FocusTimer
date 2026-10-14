import Foundation
import Combine
import AVFoundation
import Speech

@MainActor
final class SpeechInput: ObservableObject {
    @Published var text = ""
    @Published var listening = false
    @Published var errorMessage: String?
    var onFinish: (() -> Void)?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognitionID = UUID()
    private var tapInstalled = false

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
            tapInstalled = true
            engine.prepare()
            try engine.start()
            listening = true
            let id = UUID()
            recognitionID = id
            task = recognizer?.recognitionTask(with:req) { [weak self] result,error in
                Task { @MainActor in
                    guard let self, self.recognitionID == id else {return}
                    if let result {
                        self.text = result.bestTranscription.formattedString
                        if result.isFinal {self.stop();return}
                    }
                    if let error {self.errorMessage = error.localizedDescription;self.stop()}
                }
            }
        } catch {errorMessage = error.localizedDescription;stop()}
    }
    func stop() {
        let wasListening = listening
        recognitionID = UUID()
        let req = request
        let currentTask = task
        task = nil
        request = nil
        if engine.isRunning {engine.stop()}
        if tapInstalled {engine.inputNode.removeTap(onBus:0);tapInstalled=false}
        req?.endAudio()
        currentTask?.cancel()
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false)
        if wasListening {
            let finish = onFinish
            onFinish = nil
            finish?()
        }
    }
}
