import XCTest

/// 本物の speech.cpp を動かすテスト。POKO_TEST_WAV に 16 kHz・16 bit・モノラルの WAV を渡したときだけ走る。
/// 例: POKO_HOME=$PWD POKO_TEST_WAV=voice.wav ./scripts/test.sh
final class TranscriptionTests: XCTestCase {
    func testStreamsAudioAndReturnsText() async throws {
        guard let path = ProcessInfo.processInfo.environment["POKO_TEST_WAV"] else {
            throw XCTSkip("POKO_TEST_WAV がないので飛ばす")
        }
        let pcm = try Self.samples(ofWAV: URL(fileURLWithPath: path))
        let session = try Transcription(files: .locate())
        // 0.1 秒ずつ、録っているときと同じように流す（待たずに）。
        let step = Transcription.sampleRate / 10 * 2
        var offset = pcm.startIndex
        while offset < pcm.endIndex {
            let end = min(offset + step, pcm.endIndex)
            session.feed(Data(pcm[offset..<end]))
            offset = end
        }
        let started = Date()
        let text = try await session.finish()
        print("離してから \(String(format: "%.3f", Date().timeIntervalSince(started))) 秒: \(text)")
        XCTAssertFalse(text.isEmpty)
    }

    func testCancelStopsTheProcess() throws {
        guard ProcessInfo.processInfo.environment["POKO_TEST_WAV"] != nil else {
            throw XCTSkip("POKO_TEST_WAV がないので飛ばす")
        }
        let session = try Transcription(files: .locate())
        session.feed(Data(count: 3200))
        session.cancel()
    }

    /// WAV の "data" チャンクの中身を返す（チャンクを順にたどる。前に別のチャンクがあってもよい）。
    static func samples(ofWAV url: URL) throws -> Data {
        let wav = try Data(contentsOf: url)
        func u32(_ at: Int) -> Int { wav[at..<at + 4].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) } }
        var at = wav.startIndex + 12
        while at + 8 <= wav.endIndex {
            let size = u32(at + 4)
            if wav[at..<at + 4] == Data("data".utf8) { return wav[(at + 8)..<min(at + 8 + size, wav.endIndex)] }
            at += 8 + size + size % 2
        }
        throw XCTSkip("WAV の data チャンクが見つからない")
    }

    func testMissingFilesAreExplained() {
        let files = EngineFiles(
            speech: URL(fileURLWithPath: "/nonexistent/speech"),
            model: URL(fileURLWithPath: "/nonexistent/model.gguf"),
            vad: URL(fileURLWithPath: "/nonexistent/vad.gguf"),
            llamaServer: URL(fileURLWithPath: "/nonexistent/llama-server"),
            gemma: URL(fileURLWithPath: "/nonexistent/gemma.gguf")
        )
        XCTAssertThrowsError(try Transcription(files: files)) { error in
            XCTAssertTrue(error.localizedDescription.contains("setup.sh"))
        }
    }
}
