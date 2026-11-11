import XCTest

/// 辞書の読み書きと、speech.cpp・推敲に渡す文字列。
final class VocabularyTests: XCTestCase {
    func testParsesLinesAndSkipsCommentsAndBlanks() {
        let terms = Vocabulary.parse("# コメント\n\nPoC=ぴーおーしー,ぽっく\n  MTG ＝ みーてぃんぐ  \nスライム\n")
        XCTAssertEqual(terms, [
            Term(written: "PoC", readings: "ぴーおーしー、ぽっく"),
            Term(written: "MTG", readings: "みーてぃんぐ"),
            Term(written: "スライム", readings: ""),
        ])
    }

    func testRoundTrip() {
        let terms = [Term(written: "PoC", readings: "ぴーおーしー、ぽっく"), Term(written: "日和坂", readings: "ひよりざか")]
        XCTAssertEqual(Vocabulary.parse(Vocabulary.serialize(terms)), terms)
        XCTAssertTrue(Vocabulary.serialize(terms).contains("PoC=ぴーおーしー,ぽっく\n"))
    }

    /// 読みの区切りは「,」「、」「，」のどれでもよく、speech.cpp には「,」で渡す。
    func testKeywordsUseCommaAndOneLinePerTerm() {
        let terms = [Term(written: "PoC", readings: "ぴーおーしー、 ぽっく，"), Term(written: "MTG", readings: "")]
        XCTAssertEqual(Vocabulary.keywords(terms), "PoC=ぴーおーしー,ぽっく\nMTG")
    }

    /// 空や空白だけを --keywords に渡すと認識が失敗するので、そのときは渡さない。
    func testNoKeywordsWhenEmpty() {
        XCTAssertNil(Vocabulary.keywords([]))
        XCTAssertNil(Vocabulary.keywords([Term(written: "  ", readings: "よみ")]))
    }

    /// 行の形を壊す文字は除く。
    func testRemovesEqualsAndNewlinesFromWritten() {
        XCTAssertEqual(Vocabulary.keywords([Term(written: "a=b\nc", readings: "えー")]), "abc=えー")
        XCTAssertEqual(Vocabulary.keywords([Term(written: "#C", readings: "しーしゃーぷ")]), "C=しーしゃーぷ")
    }

    func testGlossaryShowsReadingsInParentheses() {
        let terms = [Term(written: "日和坂", readings: "ひよりざか"), Term(written: "PoC", readings: "")]
        XCTAssertEqual(Vocabulary.glossary(terms), "日和坂（ひよりざか）\nPoC")
        XCTAssertNil(Vocabulary.glossary([]))
    }

    func testHints() {
        XCTAssertNotNil(Vocabulary.hint(for: Term(written: "PoC", readings: "")))         // 読みがない
        XCTAssertNil(Vocabulary.hint(for: Term(written: "スライム", readings: "")))         // 仮名ならそのまま読める
        XCTAssertNotNil(Vocabulary.hint(for: Term(written: "Mogu", readings: "もぐ")))     // 読みが短い
        XCTAssertNotNil(Vocabulary.hint(for: Term(written: "日和坂", readings: "ひよりざか"))) // 漢字
        XCTAssertNil(Vocabulary.hint(for: Term(written: "PoC", readings: "ぴーおーしー")))
        XCTAssertNil(Vocabulary.hint(for: Term(written: "", readings: "")))                // 書きかけ
        XCTAssertNotNil(Vocabulary.hint(for: Term(written: "PoC", readings: "poc")))       // 仮名でない読み
        XCTAssertNil(Vocabulary.hint(for: Term(written: "PoC", readings: "ピーオーシー")))  // カタカナでもよい
    }

    func testPolishPromptAddsGlossaryOnlyWhenGiven() {
        XCTAssertEqual(PolishPrompt.system(glossary: nil), PolishPrompt.system)
        let prompt = PolishPrompt.system(glossary: "日和坂（ひよりざか）")
        XCTAssertTrue(prompt.hasPrefix(PolishPrompt.system))
        XCTAssertTrue(prompt.contains("<glossary>\n日和坂（ひよりざか）\n</glossary>"))
    }

    func testActivityKeepsNewestFirstAndDropsRawWhenUnchanged() async {
        await MainActor.run {
            let activity = Activity()
            activity.add(text: "一つ目", raw: "一つ目", note: nil)
            activity.add(text: "二つ目。", raw: "えー、二つ目", note: nil)
            XCTAssertEqual(activity.entries.map(\.text), ["二つ目。", "一つ目"])
            XCTAssertNil(activity.entries[1].raw)
            XCTAssertEqual(activity.entries[0].raw, "えー、二つ目")
        }
    }
}
