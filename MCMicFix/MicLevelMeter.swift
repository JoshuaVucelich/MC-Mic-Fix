import Foundation
import AVFoundation
import Accelerate

@MainActor
@Observable
final class MicLevelMeter {
    /// 0...1 smoothed RMS level for UI.
    private(set) var level: Float = 0
    private(set) var isRunning = false

    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var autoStopTask: Task<Void, Never>?

    /// Starts metering. Call only while the mic-test UI is intentionally open.
    /// Auto-stops after `autoStopAfter` (default 60s).
    func start(autoStopAfter: Duration = .seconds(60)) {
        guard !isRunning else {
            scheduleAutoStop(after: autoStopAfter)
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            level = 0
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            level = 0
            return
        }

        // B1: Core Audio invokes the tap on the realtime audio thread.
        // The closure must be @Sendable and must not touch MainActor APIs
        // except via an explicit hop after computing RMS off-actor.
        installInputTap(on: input, format: format)
        tapInstalled = true

        do {
            try engine.start()
            self.engine = engine
            isRunning = true
            scheduleAutoStop(after: autoStopAfter)
        } catch {
            if tapInstalled {
                input.removeTap(onBus: 0)
                tapInstalled = false
            }
            self.engine = nil
            isRunning = false
            level = 0
            NSLog("MicLevelMeter start failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        autoStopTask?.cancel()
        autoStopTask = nil
        guard isRunning || engine != nil else {
            level = 0
            return
        }
        if tapInstalled {
            engine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine?.stop()
        engine = nil
        isRunning = false
        level = 0
    }

    private func scheduleAutoStop(after duration: Duration) {
        autoStopTask?.cancel()
        autoStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    /// nonisolated so the compiler does not infer a main-actor tap closure.
    nonisolated private func installInputTap(on input: AVAudioInputNode, format: AVAudioFormat) {
        // installTap is deprecated in macOS 27 but still the practical metering path.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable [weak self] buffer, _ in
            let rms = Self.rms(of: buffer)
            let mapped = min(1, max(0, rms * 8))
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.level = self.level * 0.6 + mapped * 0.4
            }
        }
    }

    nonisolated private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var meanSquares: Float = 0
        vDSP_measqv(channelData, 1, &meanSquares, vDSP_Length(frameLength))
        return sqrtf(meanSquares)
    }
}
