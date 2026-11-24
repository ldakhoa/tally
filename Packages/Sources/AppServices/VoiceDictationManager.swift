import Foundation
import Observation
import TallyCore

#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Speech)
import Speech
#endif

/// Supported voice dictation languages for automatic detection (Vietnamese, English, Simplified Chinese).
public enum DictationLanguage: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case vietnamese = "vi-VN"
    case english = "en-SG"
    case chinese = "zh-CN"

    public var id: String { rawValue }

    public var flag: String {
        switch self {
        case .vietnamese: return "🇻🇳"
        case .english: return "🇬🇧"
        case .chinese: return "🇨🇳"
        }
    }

    public var shortLabel: String {
        switch self {
        case .vietnamese: return "VI"
        case .english: return "EN"
        case .chinese: return "中文"
        }
    }

    public var nativeName: String {
        switch self {
        case .vietnamese: return "Tiếng Việt"
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    public var fallbackLocaleIdentifier: String {
        switch self {
        case .vietnamese: return "vi-VN"
        case .english: return "en-US"
        case .chinese: return "zh-Hans-CN"
        }
    }

    public init(appLanguage: AppLanguage) {
        switch appLanguage.resolved {
        case .vietnamese: self = .vietnamese
        case .chinese: self = .chinese
        case .english: self = .english
        }
    }
}

/// Real-time auto-detecting voice dictation across Vietnamese, English, and Chinese.
/// Feeds the live microphone buffer into concurrent speech recognizers and ranks their transcripts.
@MainActor
@Observable
public final class VoiceDictationManager {
    public private(set) var detectedLanguage: DictationLanguage?
    public private(set) var isRecording = false
    public private(set) var transcript = ""
    public private(set) var audioLevel: Float = 0
    public private(set) var errorMessage: String?

    #if canImport(AVFoundation) && canImport(Speech)
    private struct Candidate {
        var text: String
        var score: Double
        var isFinal: Bool
    }

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var activeRequests: [DictationLanguage: SFSpeechAudioBufferRecognitionRequest] = [:]
    @ObservationIgnored private var activeTasks: [DictationLanguage: SFSpeechRecognitionTask] = [:]
    @ObservationIgnored private var candidates: [DictationLanguage: Candidate] = [:]
    @ObservationIgnored private var sessionID: UUID?
    #endif

    public init() {}

    public func toggle(
        appLanguage: AppLanguage,
        onTranscript: @escaping @MainActor (String) -> Void
    ) {
        if isRecording {
            stop()
        } else {
            start(appLanguage: appLanguage, onTranscript: onTranscript)
        }
    }

    public func start(
        appLanguage: AppLanguage,
        onTranscript: @escaping @MainActor (String) -> Void
    ) {
        errorMessage = nil
        #if canImport(AVFoundation) && canImport(Speech)
        Task {
            let speechOK = await requestSpeechAuthorization()
            guard speechOK else {
                self.errorMessage = L10n.text(
                    appLanguage,
                    en: "Enable Speech Recognition for Tally in iOS Settings.",
                    vi: "Hãy bật quyền Nhận dạng giọng nói cho Tally trong Cài đặt iOS.",
                    zh: "请在 iOS 设置中为 Tally 开启语音识别权限。"
                )
                return
            }

            let micOK = await requestMicrophonePermission()
            guard micOK else {
                self.errorMessage = L10n.text(
                    appLanguage,
                    en: "Enable Microphone access for Tally in iOS Settings.",
                    vi: "Hãy bật quyền Micro cho Tally trong Cài đặt iOS.",
                    zh: "请在 iOS 设置中为 Tally 开启麦克风权限。"
                )
                return
            }

            self.beginAutoDetectSession(appLanguage: appLanguage, onTranscript: onTranscript)
        }
        #else
        errorMessage = L10n.text(
            appLanguage,
            en: "Voice dictation is not available on this platform.",
            vi: "Nhập giọng nói không khả dụng trên thiết bị này.",
            zh: "此设备不支持语音听写。"
        )
        #endif
    }

    public func stop() {
        #if canImport(AVFoundation) && canImport(Speech)
        sessionID = nil
        for request in activeRequests.values {
            request.endAudio()
        }
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
        activeRequests.removeAll()
        candidates.removeAll()

        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        #endif

        isRecording = false
        audioLevel = 0
    }

    // MARK: - Concurrent Multi-Locale Speech Recognition

    #if canImport(AVFoundation) && canImport(Speech)
    private func beginAutoDetectSession(
        appLanguage: AppLanguage,
        onTranscript: @escaping @MainActor (String) -> Void
    ) {
        stop()
        let preferredDefault = DictationLanguage(appLanguage: appLanguage)
        detectedLanguage = nil

        let supportedLocales = SFSpeechRecognizer.supportedLocales()
        func localeKey(_ locale: Locale) -> String {
            locale.language.maximalIdentifier
        }
        var recognizers: [(DictationLanguage, SFSpeechRecognizer)] = []
        for lang in DictationLanguage.allCases {
            for identifier in [lang.rawValue, lang.fallbackLocaleIdentifier] {
                let key = localeKey(Locale(identifier: identifier))
                guard let locale = supportedLocales.first(where: { localeKey($0) == key }),
                      let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable,
                      localeKey(recognizer.locale) == key else { continue }
                recognizers.append((lang, recognizer))
                break
            }
        }

        guard !recognizers.isEmpty else {
            errorMessage = L10n.text(
                appLanguage,
                en: "Speech recognition is temporarily unavailable.",
                vi: "Nhận dạng giọng nói tạm thời không khả dụng.",
                zh: "语音识别暂时不可用。"
            )
            return
        }

        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        #endif

        let contextualVocab = [
            "PayNow", "FairPrice", "Grab", "SimplyGo", "MRT", "SGD", "VND", "Tally",
            "tiền nhà", "thẻ tín dụng", "ngân sách", "tiết kiệm", "mục tiêu",
            "房租", "信用卡", "预算", "存钱", "目标", "餐饮", "超市",
        ]

        var requestsToFeed: [SFSpeechAudioBufferRecognitionRequest] = []
        for (lang, _) in recognizers {
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.taskHint = .dictation
            req.addsPunctuation = true
            req.contextualStrings = contextualVocab
            activeRequests[lang] = req
            requestsToFeed.append(req)
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let sessionID = UUID()

        self.sessionID = sessionID
        self.audioEngine = engine
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            for req in requestsToFeed {
                req.append(buffer)
            }
            let level = Self.computeNormalizedPower(buffer: buffer)
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == sessionID else { return }
                self.audioLevel = level
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            errorMessage = error.localizedDescription
            stop()
            return
        }

        self.transcript = ""
        self.isRecording = true

        for (lang, recognizer) in recognizers {
            guard let request = activeRequests[lang] else { continue }
            activeTasks[lang] = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == sessionID, self.activeTasks[lang] != nil else { return }
                    if let result, error == nil || result.isFinal {
                        let transcription = result.bestTranscription
                        let text = transcription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        if text.isEmpty {
                            self.candidates.removeValue(forKey: lang)
                        } else {
                            let score = DictationRanking.score(
                                text: text,
                                language: lang,
                                confidences: transcription.segments.map { Double($0.confidence) },
                                isFinal: result.isFinal
                            )
                            self.candidates[lang] = Candidate(text: text, score: score, isFinal: result.isFinal)
                        }
                    }
                    if error != nil {
                        if self.candidates[lang]?.isFinal != true {
                            self.candidates.removeValue(forKey: lang)
                        }
                        self.activeTasks.removeValue(forKey: lang)
                    }
                    let winner = DictationRanking.winner(
                        scores: self.candidates.mapValues(\.score),
                        preferred: preferredDefault,
                        current: self.detectedLanguage
                    )
                    self.detectedLanguage = winner
                    if let winner, let candidate = self.candidates[winner], candidate.text != self.transcript {
                        self.transcript = candidate.text
                        onTranscript(candidate.text)
                    }
                    if self.activeTasks.isEmpty {
                        self.stop()
                    }
                }
            }
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return true }
        if current == .denied || current == .restricted { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #elseif os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
        #else
        return true
        #endif
    }

    private nonisolated static func computeNormalizedPower(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        let db = 20 * log10(max(rms, 0.00001))
        let normalized = (db + 50) / 45
        return min(1, max(0.05, normalized))
    }
    #endif
}
