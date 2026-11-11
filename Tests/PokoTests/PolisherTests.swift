import XCTest

/// 推敲が失敗しても文を失わないこと。Polisher を通して確かめる。
@MainActor
final class PolisherTests: XCTestCase {
    private var saved: PolishMode = .off

    override func setUp() async throws {
        saved = PolishMode.current
    }

    override func tearDown() async throws {
        PolishMode.current = saved  // 選んだものを元に戻す
    }

    private func files(server: String, model: String) -> EngineFiles {
        EngineFiles(
            speech: URL(fileURLWithPath: "/nonexistent/speech"),
            model: URL(fileURLWithPath: "/nonexistent/model.gguf"),
            vad: URL(fileURLWithPath: "/nonexistent/vad.gguf"),
            llamaServer: URL(fileURLWithPath: server),
            gemma: URL(fileURLWithPath: model)
        )
    }

    func testOffReturnsTextAsIs() async {
        PolishMode.current = .off
        let polisher = Polisher(files: files(server: "/nonexistent/llama-server", model: "/nonexistent/gemma.gguf"))
        let result = await polisher.polish("えー、はい")
        XCTAssertEqual(result.text, "えー、はい")
        XCTAssertNil(result.note)
    }

    /// llama.cpp やモデルがなければ、元の文と理由を返す。
    func testMissingFilesKeepOriginal() async {
        PolishMode.current = .local
        let polisher = Polisher(files: files(server: "/nonexistent/llama-server", model: "/nonexistent/gemma.gguf"))
        XCTAssertNotNil(polisher.problem())
        let result = await polisher.polish("えー、はい")
        XCTAssertEqual(result.text, "えー、はい")
        XCTAssertTrue(result.note?.contains("setup.sh --llm") ?? false, result.note ?? "")
    }

    /// llama-server がすぐ終わってしまっても、元の文と理由を返す。
    func testServerThatExitsKeepsOriginal() async {
        PolishMode.current = .local
        let polisher = Polisher(files: files(server: "/usr/bin/false", model: "/etc/hosts"))
        defer { polisher.stop() }
        let result = await polisher.polish("えー、はい")
        XCTAssertEqual(result.text, "えー、はい")
        XCTAssertTrue(result.note?.contains("推敲せずに貼りました") ?? false, result.note ?? "")
    }

    /// 本物の Gemma で、選ぶところから推敲まで通す。POKO_TEST_LLM に local があるときだけ。
    func testLocalPolishEndToEnd() async throws {
        let list = ProcessInfo.processInfo.environment["POKO_TEST_LLM"]?.components(separatedBy: ",") ?? []
        guard list.contains("local") else { throw XCTSkip("POKO_TEST_LLM に local がないので飛ばす") }
        PolishMode.current = .local
        let polisher = Polisher(files: .locate())
        defer { polisher.stop() }
        polisher.prepare()  // 押して 0.3 秒経ったときと同じ
        let raw = "えーっと、あの、明日は、まあ、10時に行きます"
        let result = await polisher.polish(raw)
        print("Polisher: \(result.text) / \(result.note ?? "理由なし")")
        XCTAssertNil(result.note)
        XCTAssertNotEqual(result.text, raw)
        XCTAssertFalse(result.text.contains("えーっと"))
    }
}
