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

    func testClaudeStreamingArguments() {
        let args = SubscriptionLLM.arguments(for: .claude, system: "指示", user: "本文", stream: true)
        XCTAssertEqual(args[args.firstIndex(of: "--output-format")! + 1], "stream-json")
        XCTAssertTrue(args.contains("--include-partial-messages"))
        XCTAssertEqual(args.last, "本文")
        XCTAssertFalse(SubscriptionLLM.arguments(for: .claude, system: "指示", user: "本文").contains("--output-format"))
    }

    func testStreamParserCollectsTextDeltas() {
        let parser = SubscriptionLLM.StreamParser()
        XCTAssertNil(parser.feed(#"{"type":"system","subtype":"init"}"#))
        XCTAssertEqual(parser.feed(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"1、"}}}"#), "1、")
        XCTAssertEqual(parser.feed(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"2"}}}"#), "1、2")
        XCTAssertNil(parser.feed("壊れた行"))
        XCTAssertNil(parser.feed(#"{"type":"result","subtype":"success","result":"1、2"}"#))
        XCTAssertEqual(parser.result, "1、2")
    }

    func testOnlyLocalKeepsTextInside() {
        XCTAssertFalse(LLMProvider.local.sendsOut)
        XCTAssertTrue(LLMProvider.claude.sendsOut)
        XCTAssertTrue(LLMProvider.chatgpt.sendsOut)
    }
}
