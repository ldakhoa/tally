import AVFoundation
import Foundation

public enum CozySoundKind: CaseIterable, Hashable, Sendable {
    case tick
    case pop
    case love
    case success

    var volume: Float {
        switch self {
        case .tick: return 0.18
        case .pop: return 0.24
        case .love: return 0.24
        case .success: return 0.22
        }
    }

    fileprivate var duration: Double {
        switch self {
        case .tick: return 0.028
        case .pop: return 0.048
        case .love: return 0.135
        case .success: return 0.22
        }
    }
}

/// Lightweight, off-main-thread synthesized UI sound engine (Facebook/Meta style).
/// Respects the iOS silent switch via `.ambient`, preserves background music,
/// yields cleanly during voice dictation, and never touches the main thread.
public enum CozySounds {
    private static let queue = DispatchQueue(label: "com.tally.cozy-sounds", qos: .userInteractive)
    private static let stateLock = NSLock()
    private nonisolated(unsafe) static var enabledFlag = true

    private nonisolated(unsafe) static var playerPools: [CozySoundKind: [AVAudioPlayer]] = [:]
    private nonisolated(unsafe) static var poolIndices: [CozySoundKind: Int] = [:]
    private nonisolated(unsafe) static var isWarmed = false
    private nonisolated(unsafe) static var isAudioSessionConfigured = false
    private nonisolated(unsafe) static var lastTickTime: CFAbsoluteTime = 0

    public static var isEnabled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return enabledFlag
    }

    public static func setEnabled(_ enabled: Bool) {
        stateLock.lock()
        enabledFlag = enabled
        stateLock.unlock()
    }

    public static func warmUp() {
        queue.async {
            ensurePoolsOnQueue()
        }
    }

    public static func play(_ kind: CozySoundKind) {
        guard isEnabled else { return }
        queue.async {
            guard isEnabled else { return }

            if kind == .tick {
                let now = CFAbsoluteTimeGetCurrent()
                if now - lastTickTime < 0.035 {
                    return
                }
                lastTickTime = now
            }

            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            let currentCategory = session.category
            if currentCategory == .record || currentCategory == .playAndRecord {
                return
            }
            if !isAudioSessionConfigured || currentCategory != .ambient {
                try? session.setCategory(.ambient, mode: .default, options: [])
                isAudioSessionConfigured = true
            }
            #endif

            ensurePoolsOnQueue()
            guard let pool = playerPools[kind], !pool.isEmpty else { return }
            let idx = poolIndices[kind] ?? 0
            let player = pool[idx % pool.count]
            poolIndices[kind] = (idx + 1) % pool.count

            player.currentTime = 0
            player.volume = kind.volume
            player.play()
        }
    }

    // MARK: - Pool & WAV Synthesis (Called Only on `queue`)

    private static func ensurePoolsOnQueue() {
        guard !isWarmed else { return }
        isWarmed = true

        for kind in CozySoundKind.allCases {
            let wavData = synthesizeWAV(for: kind)
            var pool: [AVAudioPlayer] = []
            pool.reserveCapacity(3)
            for _ in 0..<3 {
                if let player = try? AVAudioPlayer(data: wavData, fileTypeHint: AVFileType.wav.rawValue) {
                    player.volume = kind.volume
                    player.prepareToPlay()
                    pool.append(player)
                }
            }
            playerPools[kind] = pool
            poolIndices[kind] = 0
        }
    }

    static func synthesizeWAV(for kind: CozySoundKind) -> Data {
        let sampleRate = 44_100
        let sampleCount = max(1, Int((kind.duration * Double(sampleRate)).rounded()))
        var samples = [Int16](repeating: 0, count: sampleCount)

        let dt = 1.0 / Double(sampleRate)
        var phase1 = 0.0
        var phase2 = 0.0

        for i in 0..<sampleCount {
            let t = Double(i) * dt
            let value: Double

            switch kind {
            case .tick:
                let progress = min(1.0, t / kind.duration)
                let freq = 540.0 + (720.0 - 540.0) * progress
                phase1 += 2.0 * .pi * freq * dt
                let attack = min(1.0, t / 0.002)
                let env = attack * exp(-t * 140.0)
                value = sin(phase1) * env * 0.75

            case .pop:
                let progress = min(1.0, t / kind.duration)
                let freq = 380.0 + (760.0 - 380.0) * progress
                phase1 += 2.0 * .pi * freq * dt
                let attack = min(1.0, t / 0.003)
                let env = attack * exp(-t * 78.0)
                let body = sin(phase1) + 0.15 * sin(phase1 * 2.0)
                value = body * env * 0.7

            case .love:
                // Bubble 1 (0.0s): 587 -> 740 Hz
                let b1Progress = min(1.0, t / 0.055)
                let f1 = 587.0 + (740.0 - 587.0) * b1Progress
                phase1 += 2.0 * .pi * f1 * dt
                let env1 = min(1.0, t / 0.003) * exp(-t * 68.0)
                var mix = sin(phase1) * env1 * 0.62

                // Bubble 2 (0.048s): 784 -> 1046 Hz
                let t2 = t - 0.048
                if t2 >= 0 {
                    let b2Progress = min(1.0, t2 / 0.08)
                    let f2 = 784.0 + (1046.0 - 784.0) * b2Progress
                    phase2 += 2.0 * .pi * f2 * dt
                    let env2 = min(1.0, t2 / 0.003) * exp(-t2 * 48.0)
                    mix += sin(phase2) * env2 * 0.68
                }
                value = mix

            case .success:
                // Cozy marimba two-note chime: C6 (1046.5 Hz) -> E6 (1318.5 Hz)
                phase1 += 2.0 * .pi * 1046.5 * dt
                let env1 = min(1.0, t / 0.003) * exp(-t * 22.0)
                var mix = (sin(phase1) + 0.12 * sin(phase1 * 2.0)) * env1 * 0.5

                let t2 = t - 0.065
                if t2 >= 0 {
                    phase2 += 2.0 * .pi * 1318.5 * dt
                    let env2 = min(1.0, t2 / 0.003) * exp(-t2 * 18.0)
                    mix += (sin(phase2) + 0.12 * sin(phase2 * 2.0)) * env2 * 0.56
                }
                value = mix
            }

            let clamped = max(-1.0, min(1.0, value))
            samples[i] = Int16(clamped * Double(Int16.max))
        }

        let dataSize = samples.count * MemoryLayout<Int16>.size
        let riffSize = UInt32(36 + dataSize)
        var data = Data(capacity: 44 + dataSize)

        func appendUInt32LE(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendUInt16LE(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        appendUInt32LE(riffSize)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        appendUInt32LE(16)                                // PCM subchunk size
        appendUInt16LE(1)                                 // PCM format
        appendUInt16LE(1)                                 // Mono
        appendUInt32LE(UInt32(sampleRate))                // Sample rate
        appendUInt32LE(UInt32(sampleRate * 2))            // Byte rate
        appendUInt16LE(2)                                 // Block align
        appendUInt16LE(16)                                // Bits per sample
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        appendUInt32LE(UInt32(dataSize))

        for sample in samples {
            var le = sample.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        return data
    }
}
