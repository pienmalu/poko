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
        XCTAssertFalse(parser.finished)
        XCTAssertNil(parser.feed(#"{"type":"result","subtype":"success","result":"1、2"}"#))
        XCTAssertEqual(parser.result, "1、2")
        XCTAssertTrue(parser.finished)
    }

    /// 失敗の知らせ（is_error）は、答えがそろったことにしない（CLI を先に止めず、失敗として扱う）。
    func testStreamParserDoesNotFinishOnAnError() {
        let parser = SubscriptionLLM.StreamParser()
        XCTAssertNil(parser.feed(#"{"type":"result","subtype":"success","is_error":true,"result":"使える枠を超えました"}"#))
        XCTAssertFalse(parser.finished)
    }

    func testEffortCanBeChosenByTheCaller() {
        let claude = SubscriptionLLM.arguments(for: .claude, system: "指示", user: "本文", effort: "low")
        XCTAssertEqual(claude[claude.firstIndex(of: "--effort")! + 1], "low")
        XCTAssertEqual(claude.last, "本文")
        let codex = SubscriptionLLM.arguments(for: .chatgpt, system: "指示", user: "本文", effort: "medium")
        XCTAssertTrue(codex.contains(#"model_reasoning_effort="medium""#))
        // 渡さないか空なら、claude には付けず、codex は決めてある深さ
        for effort in [nil, "", " "] as [String?] {
            XCTAssertFalse(SubscriptionLLM.arguments(for: .claude, system: "指示", user: "本文", effort: effort).contains("--effort"))
            XCTAssertTrue(SubscriptionLLM.arguments(for: .chatgpt, system: "指示", user: "本文", effort: effort)
                .contains("model_reasoning_effort=\"\(SubscriptionLLM.codexEffort)\""))
        }
    }

    func testModelCanBeChosenByTheCaller() {
        let claude = SubscriptionLLM.arguments(for: .claude, system: "指示", user: "本文", model: "opus")
        XCTAssertEqual(claude[claude.firstIndex(of: "--model")! + 1], "opus")
        let codex = SubscriptionLLM.arguments(for: .chatgpt, system: "指示", user: "本文", model: "gpt-x")
        XCTAssertEqual(codex[codex.firstIndex(of: "-m")! + 1], "gpt-x")
        // 渡さないか空なら、決めてあるモデル
        for model in [nil, "", " "] as [String?] {
            let args = SubscriptionLLM.arguments(for: .claude, system: "指示", user: "本文", model: model)
            XCTAssertEqual(args[args.firstIndex(of: "--model")! + 1], SubscriptionLLM.claudeModel)
        }
    }

    /// API キーが環境変数にあっても、CLI には渡さない（サブスクのログインで動かす）。
    func testEnvironmentDropsAPIKeys() {
        let base = ["ANTHROPIC_API_KEY": "sk-a", "ANTHROPIC_AUTH_TOKEN": "t", "OPENAI_API_KEY": "sk-o", "CLAUDE_CODE_USE_BEDROCK": "1",
                    "HOME": "/Users/me", "PATH": "/somewhere"]
        let environment = SubscriptionLLM.environment(from: base, executable: URL(fileURLWithPath: "/opt/homebrew/bin/claude"))
        for name in SubscriptionLLM.apiKeyVariables { XCTAssertNil(environment[name], name) }
        XCTAssertEqual(environment["HOME"], "/Users/me")
        XCTAssertTrue(environment["PATH"]?.hasPrefix("/opt/homebrew/bin:") == true)
    }

    func testStreamParserReadsTheModelAndTheKeySource() {
        let parser = SubscriptionLLM.StreamParser()
        XCTAssertNil(parser.session)
        XCTAssertNil(parser.feed(#"{"type":"system","subtype":"init","model":"claude-sonnet-5-5","apiKeySource":"none"}"#))
        XCTAssertEqual(parser.session, SubscriptionLLM.Session(model: "claude-sonnet-5-5", apiKeySource: "none"))
    }

    func testOnlyLocalKeepsTextInside() {
        XCTAssertFalse(LLMProvider.local.sendsOut)
        XCTAssertTrue(LLMProvider.claude.sendsOut)
        XCTAssertTrue(LLMProvider.chatgpt.sendsOut)
    }
}
