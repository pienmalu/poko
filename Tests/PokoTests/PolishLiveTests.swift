import XCTest

/// 本物の LLM で推敲するテスト。POKO_TEST_LLM に local・claude・chatgpt を（カンマ区切りで）渡したときだけ走る。
/// claude と chatgpt は文字を外に送り、サブスクの枠を少し使う。
/// Dock から開いたときと同じく PATH がほぼ空でも動くかを見るには、env -i を付けて走らせる:
///   env -i HOME=$HOME PATH=/usr/bin:/bin POKO_HOME=$PWD POKO_TEST_LLM=local,claude,chatgpt ./scripts/test.sh
@MainActor
final class PolishLiveTests: XCTestCase {
    let draft = "えーっと、あの、明日のミーティングなんですけど、えー、11時からに、まあ変更してもらえますか、なんか会議室が取れなくて"

    private func wanted(_ provider: LLMProvider) throws {
        let list = ProcessInfo.processInfo.environment["POKO_TEST_LLM"]?.components(separatedBy: ",") ?? []
        guard list.contains(provider.rawValue) else { throw XCTSkip("POKO_TEST_LLM に \(provider.rawValue) がないので飛ばす") }
    }

    private func check(_ output: String, _ started: Date, _ label: String) {
        print("\(label) \(String(format: "%.2f", Date().timeIntervalSince(started))) 秒: \(output)")
        let accepted = PolishPrompt.accept(output, original: draft)
        XCTAssertNotNil(accepted)
        XCTAssertFalse(accepted?.contains("えー") ?? true)
    }

    func testLocalGemma() async throws {
        try wanted(.local)
        let files = EngineFiles.locate()
        let llm = LocalLLM(server: files.llamaServer, model: files.gemma, name: "dev.haruka.poko.tests")
        defer { llm.stop() }
        var started = Date()
        _ = try await llm.endpoint()
        print("Gemma の起動 \(String(format: "%.2f", Date().timeIntervalSince(started))) 秒")
        started = Date()
        let output = try await llm.complete(system: PolishPrompt.system, user: PolishPrompt.user(draft))
        check(output, started, "Gemma")
    }

    func testClaude() async throws {
        try wanted(.claude)
        let started = Date()
        let output = try await SubscriptionLLM.complete(.claude, system: PolishPrompt.system,
                                                        user: PolishPrompt.user(draft), timeout: 30)
        check(output, started, "Claude")
    }

    func testChatGPT() async throws {
        try wanted(.chatgpt)
        let started = Date()
        let output = try await SubscriptionLLM.complete(.chatgpt, system: PolishPrompt.system,
                                                        user: PolishPrompt.user(draft), timeout: 30)
        check(output, started, "ChatGPT")
    }

    /// 辞書を用語集として渡すと、認識が同じ読みの別の字で書いた語（鷲尾 → 鷲生）を直すか。
    func testGlossaryFixesHomophone() async throws {
        let list = ProcessInfo.processInfo.environment["POKO_TEST_LLM"]?.components(separatedBy: ",") ?? []
        let draft = "えー、明日は鷲尾さんと、あの、ひよりざかの研究室で会います"
        let glossary = Vocabulary.glossary([Term(written: "鷲生", readings: "わしお"), Term(written: "日和坂", readings: "ひよりざか")])
        let system = PolishPrompt.system(glossary: glossary)
        var ran = false
        for provider in [LLMProvider.local, .claude, .chatgpt] where list.contains(provider.rawValue) {
            ran = true
            let started = Date()
            let output: String
            if provider == .local {
                let files = EngineFiles.locate()
                let llm = LocalLLM(server: files.llamaServer, model: files.gemma, name: "dev.haruka.poko.tests")
                defer { llm.stop() }
                output = try await llm.complete(system: system, user: PolishPrompt.user(draft))
            } else {
                output = try await SubscriptionLLM.complete(provider, system: system, user: PolishPrompt.user(draft), timeout: 30)
            }
            print("用語集 \(provider.rawValue) \(String(format: "%.2f", Date().timeIntervalSince(started))) 秒: \(output)")
            let accepted = PolishPrompt.accept(output, original: draft) ?? ""
            XCTAssertTrue(accepted.contains("鷲生"), accepted)
            XCTAssertTrue(accepted.contains("日和坂"), accepted)
        }
        if !ran { throw XCTSkip("POKO_TEST_LLM がないので飛ばす") }
    }
}
