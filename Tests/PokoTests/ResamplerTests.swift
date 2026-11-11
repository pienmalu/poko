import AVFoundation
import XCTest

final class ResamplerTests: XCTestCase {
    /// マイクによくある 48 kHz・float・2 ch を、0.1 秒ずつ渡して 16 kHz・16 bit・モノラルにする。
    func testConvertsMicrophoneFormatInPieces() throws {
        let source = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let resampler = try XCTUnwrap(Resampler(from: source))
        var output = Data()
        var phase = 0.0
        for _ in 0..<10 {
            let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4800)!
            buffer.frameLength = 4800
            for frame in 0..<4800 {
                let value = Float(0.5 * sin(phase))  // 440 Hz、振幅 0.5
                buffer.floatChannelData![0][frame] = value
                buffer.floatChannelData![1][frame] = value
                phase += 2 * .pi * 440 / 48000
            }
            output += try XCTUnwrap(resampler.convert(buffer))
        }
        let samples = output.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        // 変換器はフィルタのために末尾の十数ミリ秒を次の buffer まで持ち越す（録音の最後の分は、離した後に録り足す 0.2 秒が補う）。
        XCTAssertEqual(Double(samples.count), 16000 - 200, accuracy: 100, "1 秒分が、持ち越しを除いて 16000 サンプル前後になる")
        let peak = Double(samples.dropFirst(1000).map { abs(Int($0)) }.max()!) / 32768
        XCTAssertEqual(peak, 0.5, accuracy: 0.05, "左右を混ぜても大きさが変わらない")
    }

    /// 本物の音声を、マイクと同じ形式・刻みで変換して認識させ、16 kHz の WAV を直接渡したときと同じ文になるか。
    /// POKO_TEST_AUDIO に 48 kHz などの音声ファイル、POKO_TEST_WAV に同じ音声の 16 kHz WAV を渡したときだけ走る。
    func testConvertedAudioIsRecognizedLikeTheOriginal() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let audio = env["POKO_TEST_AUDIO"], let wav = env["POKO_TEST_WAV"] else {
            throw XCTSkip("POKO_TEST_AUDIO と POKO_TEST_WAV がないので飛ばす")
        }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: audio))
        let resampler = try XCTUnwrap(Resampler(from: file.processingFormat))
        let converted = try Transcription(files: .locate())
        let chunk = AVAudioFrameCount(file.processingFormat.sampleRate / 10)
        while file.framePosition < file.length {
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk)!
            try file.read(into: buffer, frameCount: chunk)
            if let pcm = resampler.convert(buffer) { converted.feed(pcm) }
        }
        let direct = try Transcription(files: .locate())
        direct.feed(try TranscriptionTests.samples(ofWAV: URL(fileURLWithPath: wav)))
        let (a, b) = (try await converted.finish(), try await direct.finish())
        print("変換して: \(a)\n直接:     \(b)")
        XCTAssertEqual(a, b)
    }
}
