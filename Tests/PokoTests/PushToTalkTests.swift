import XCTest

final class PushToTalkTests: XCTestCase {
    func testHoldAndReleaseTranscribes() {
        var flow = PushToTalk()
        XCTAssertEqual(flow.handle(.keyDown(at: 10)), .start)
        XCTAssertEqual(flow.handle(.keyUp(at: 12)), .finish)
        XCTAssertEqual(flow.state, .transcribing)
        XCTAssertNil(flow.handle(.finished))
        XCTAssertEqual(flow.state, .idle)
    }

    func testQuickTapIsDiscarded() {
        var flow = PushToTalk()
        _ = flow.handle(.keyDown(at: 10))
        XCTAssertEqual(flow.handle(.keyUp(at: 10.1)), .cancel)
        XCTAssertEqual(flow.state, .idle)
    }

    func testShortcutWhileHoldingIsDiscarded() {
        var flow = PushToTalk()
        _ = flow.handle(.keyDown(at: 10))
        XCTAssertEqual(flow.handle(.otherInput), .cancel)
        XCTAssertNil(flow.handle(.keyUp(at: 12)), "離したときには、もう何もしない")
        XCTAssertEqual(flow.state, .idle)
    }

    func testTimeLimitTranscribesWithoutWaitingForRelease() {
        var flow = PushToTalk()
        _ = flow.handle(.keyDown(at: 10))
        XCTAssertEqual(flow.handle(.timeLimit), .finish)
        XCTAssertNil(flow.handle(.keyUp(at: 200)), "上限で認識を始めた後に離しても、二度は認識しない")
        XCTAssertEqual(flow.state, .transcribing)
    }

    func testPressWhileTranscribingIsIgnored() {
        var flow = PushToTalk()
        _ = flow.handle(.keyDown(at: 10))
        _ = flow.handle(.keyUp(at: 11))
        XCTAssertNil(flow.handle(.keyDown(at: 11.2)))
        XCTAssertNil(flow.handle(.otherInput))
        XCTAssertEqual(flow.state, .transcribing)
    }

    func testOtherInputWhileIdleDoesNothing() {
        var flow = PushToTalk()
        XCTAssertNil(flow.handle(.otherInput))
        XCTAssertNil(flow.handle(.keyUp(at: 1)))
        XCTAssertNil(flow.handle(.timeLimit))
        XCTAssertEqual(flow.state, .idle)
    }
}

final class TranscriptTests: XCTestCase {
    func testJoinsRegionsAsTheyCome() {
        XCTAssertEqual(Transcript.join(["今日は晴れです。", "明日は雨です。"]), "今日は晴れです。明日は雨です。")
    }

    func testRegionWithoutPunctuationGetsAComma() {
        XCTAssertEqual(Transcript.join(["えーと", "会議は3時からです"]), "えーと、会議は3時からです")
    }

    func testDropsEmptyLinesAndTrailingNewline() {
        XCTAssertEqual(Transcript.join(output: "\n明日の会議は午後3時からです。\n\n"), "明日の会議は午後3時からです。")
        XCTAssertEqual(Transcript.join(output: ""), "")
    }

    func testKeepsTheTextOfOneRegionAsItIs() {
        XCTAssertEqual(Transcript.join(["Hello world"]), "Hello world")
    }
}

final class IconMotionTests: XCTestCase {
    /// 待っている形に戻ったら、描き直しを止められる（電池を使い続けない）。
    func testSettlesAfterTranscribing() {
        var motion = IconMotion()
        motion.set(.transcribing, at: 0)
        var time = 0.0
        for _ in 0..<30 { _ = motion.advance(by: 1.0 / 60, at: time); time += 1.0 / 60 }
        motion.set(.idle, at: time, pop: true)
        var moving = true
        var frames = 0
        while moving && frames < 600 {
            moving = motion.advance(by: 1.0 / 60, at: time)
            time += 1.0 / 60
            frames += 1
        }
        XCTAssertFalse(moving)
        XCTAssertLessThan(frames, 120, "2 秒以内に止まる")
        for (height, rest) in zip(motion.heights, IconMotion.rest) {
            XCTAssertEqual(height, rest, accuracy: 0.05)
        }
    }

    func testRecordingFollowsTheVoice() {
        var quiet = IconMotion()
        var loud = IconMotion()
        quiet.set(.recording, at: 0)
        loud.set(.recording, at: 0)
        var time = 0.0
        for frame in 0..<30 {
            if frame % 6 == 0 {  // マイクからは 0.1 秒ごとに届く
                quiet.hear(0)
                loud.hear(1)
            }
            _ = quiet.advance(by: 1.0 / 60, at: time)
            _ = loud.advance(by: 1.0 / 60, at: time)
            time += 1.0 / 60
        }
        XCTAssertEqual(quiet.heights.max()!, IconMotion.dot, accuracy: 0.1, "黙っていれば点のまま")
        XCTAssertGreaterThan(loud.heights[2], 9, "声を出せば真ん中が伸びる")
        XCTAssertLessThanOrEqual(loud.heights.max()!, IconDrawing.size.height)
    }
}
