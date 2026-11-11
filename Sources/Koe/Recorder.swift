import AVFoundation

/// マイクの音を 16 kHz・モノラル・16 bit に変えて渡す。マイクを使うのは押している間だけ。
final class Recorder {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 変換した音。録音のスレッドから呼ばれる。
    var onAudio: ((Data) -> Void)?
    /// 声の大きさ（0〜1）。録音のスレッドから呼ばれる。
    var onLevel: ((Float) -> Void)?

    private var engine: AVAudioEngine?

    /// 録り始めるたびにエンジンを作り直す。マイクを差し替えても、そのときの入力を使える。
    func start() throws {
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0 else {
            throw Failure(message: "マイクが見つかりません")
        }
        guard let resampler = Resampler(from: source) else {
            throw Failure(message: "マイクの音を変換できません（\(source)）")
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: source) { [weak self] buffer, _ in
            guard let self else { return }
            onLevel?(Self.level(of: buffer))
            if let pcm = resampler.convert(buffer) { onAudio?(pcm) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw Failure(message: "マイクを使えません: \(error.localizedDescription)")
        }
        self.engine = engine
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    /// 1つ目のチャンネルの RMS を dB にし、-55〜-10 dB を 0〜1 に割り当てる。
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            sum += channel[i] * channel[i]
        }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 1e-7))
        return min(max((decibels + 55) / 45, 0), 1)
    }
}

/// マイクの形式（48 kHz・float・2 ch など）の音を、speech.cpp に渡す 16 kHz・16 bit・モノラルに変える。
/// 続けて届く buffer を順に渡す（変換の途中の状態を buffer の間で引き継ぐ）。
final class Resampler {
    static let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(Transcription.sampleRate),
        channels: 1,
        interleaved: true
    )!

    private let converter: AVAudioConverter

    init?(from source: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: source, to: Self.format) else { return nil }
        converter.downmix = true  // 2 ch 以上なら、片方を捨てずに混ぜる
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        let ratio = Self.format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: capacity) else { return nil }
        var handedOver = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if handedOver {
                status.pointee = .noDataNow  // 次の buffer が来るまで待つ
                return nil
            }
            handedOver = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, converted.frameLength > 0, let samples = converted.int16ChannelData else { return nil }
        return Data(bytes: samples[0], count: Int(converted.frameLength) * MemoryLayout<Int16>.size)
    }
}
