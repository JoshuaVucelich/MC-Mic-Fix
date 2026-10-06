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

    func start() {
        guard !isRunning else { return }
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

        installInputTap(on: input, format: format)
        tapInstalled = true

        do {
            try engine.start()
            self.engine = engine
            isRunning = true
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

    /// Isolated so we can acknowledge the macOS 27 deprecation in one place.
    private func installInputTap(on input: AVAudioInputNode, format: AVAudioFormat) {
        // AVAudioNode.installTap is deprecated in macOS 27 but remains the supported
        // way to read input levels without a full Voice-Processing IO unit setup.
        // Revisit when Apple documents a non-deprecated replacement for metering.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let rms = Self.rms(of: buffer)
            Task { @MainActor in
                let mapped = min(1, max(0, rms * 8))
                self?.level = (self?.level ?? 0) * 0.6 + mapped * 0.4
            }
        }
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var meanSquares: Float = 0
        vDSP_measqv(channelData, 1, &meanSquares, vDSP_Length(frameLength))
        return sqrtf(meanSquares)
    }
}
