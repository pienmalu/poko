import XCTest

/// 推敲の答えの確かめ方と、CLI に渡す引数。LLM は動かさない。
final class PolishTests: XCTestCase {
    let original = "えーっと、あの、明日のミーティングなんですけど、えー、11時からに変更してもらえますか"

    func testAcceptsShorterText() {
        XCTAssertEqual(PolishPrompt.accept("明日のミーティング、11時からに変更してもらえますか。\n", original: original),
                       "明日のミーティング、11時からに変更してもらえますか。")
    }

    func testStripsTagsAndCodeFence() {
        XCTAssertEqual(PolishPrompt.accept("```\n<transcript>はい。</transcript>\n```", original: "えー、はい"), "はい。")
    }

    func testRejectsEmpty() {
        XCTAssertNil(PolishPrompt.accept("  \n", original: original))
    }

    /// 中身の質問に答えてしまった（元よりずっと長い）ものは使わない。
    func testRejectsAnswerInsteadOfRewrite() {
        let answer = "明日の天気は晴れのち曇りで、最高気温は 18 度の予報です。傘は要らないでしょう。"
        XCTAssertNil(PolishPrompt.accept(answer, original: "明日の天気調べて"))
    }

    func testRejectsTooShortForLongInput() {
        XCTAssertNil(PolishPrompt.accept("はい。", original: original))
    }

    /// フィラーばかりの短い文は、大きく縮んでもよい。
    func testAllowsShortFillerOnlyInput() {
        XCTAssertEqual(PolishPrompt.accept("はい。", original: "えー、あの、まあ、はい"), "はい。")
    }

    func testWrapsTranscript() {
        XCTAssertEqual(PolishPrompt.user("こんにちは"), "<transcript>こんにちは</transcript>")
    }

    func testClaudeArgumentsReadNoSettings() {
        let args = SubscriptionLLM.arguments(for: .claude, system: "指示", user: "本文")
        XCTAssertEqual(args.first, "-p")
        XCTAssertEqual(args.last, "本文")
        XCTAssertFalse(args.contains("--bare"))  // --bare はサブスクのログインを読まない
        for flag in ["--setting-sources", "--strict-mcp-config", "--no-session-persistence", "--tools"] {
            XCTAssertTrue(args.contains(flag), flag)
        }
    }

    func testCodexArgumentsAreReadOnlyAndEphemeral() {
        let args = SubscriptionLLM.arguments(for: .chatgpt, system: "指示", user: "本文")
        XCTAssertEqual(args.first, "exec")
        XCTAssertEqual(args.last, "指示\n\n本文")
        XCTAssertTrue(args.contains("--ephemeral"))
        XCTAssertEqual(args[args.firstIndex(of: "-s")! + 1], "read-only")
    }

    func testOnlyLocalKeepsTextInside() {
        XCTAssertFalse(LLMProvider.local.sendsOut)
        XCTAssertTrue(LLMProvider.claude.sendsOut)
        XCTAssertTrue(LLMProvider.chatgpt.sendsOut)
    }
}
