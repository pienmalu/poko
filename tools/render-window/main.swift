// 窓の見た目を、ライトとダーク、空のときと語や結果が入ったときで PNG に描く（見た目の確認用）。
// 使い方: ./tools/render-window.sh [出力フォルダ]
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/window")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

func settle(_ seconds: Double = 0.6) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

@MainActor
func render(_ name: String, dark: Bool, terms: [Term], pane: Activity.Pane, phase: Activity.Phase = .idle,
            entries: [(String, String, String?)] = [], notice: String? = nil) {
    let dictionary = FileManager.default.temporaryDirectory.appendingPathComponent("poko-render-\(name).txt")
    try? Vocabulary.serialize(terms).write(to: dictionary, atomically: true, encoding: .utf8)
    setenv("POKO_DICTIONARY", dictionary.path, 1)
    let activity = Activity()
    let base = Date(timeIntervalSince1970: 1_794_000_000)
    for (i, entry) in entries.reversed().enumerated() {
        activity.add(text: entry.0, raw: entry.1, note: entry.2, at: base.addingTimeInterval(Double(i) * 97))
    }
    activity.pane = pane
    activity.phase = phase
    activity.notice = notice
    let window = MainWindow.makeWindow(activity: activity, vocabulary: VocabularyStore())
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.setFrame(NSRect(x: 80, y: 80, width: 520, height: 560), display: true)
    window.orderFrontRegardless()
    settle()
    let file = out.appendingPathComponent("\(name).png")
    // 本物の窓を撮る（ツールバーの素材まで正しく写る）。画面収録の許可がなければ、中身だけを描く。
    let shot = Process()
    shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    shot.arguments = ["-x", "-o", "-l\(window.windowNumber)", file.path]
    try? shot.run()
    shot.waitUntilExit()
    if shot.terminationStatus != 0 || !FileManager.default.fileExists(atPath: file.path) {
        let frame = window.contentView!.superview!
        let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds)!
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])!.write(to: file)
        print("\(name): 画面を撮れないので、中身だけを描きました")
    }
    window.orderOut(nil)
}

let terms = [
    Term(written: "PoC", readings: "ぴーおーしー、ぽっく"),
    Term(written: "MTG", readings: "えむてぃーじー"),
    Term(written: "llama-server", readings: "らまさーばー"),
    Term(written: "Silero", readings: "しれろ"),
    Term(written: "日和坂", readings: "ひよりざか"),
    Term(written: "Mogu", readings: "もぐ"),
    Term(written: "FastConformer", readings: ""),
]
let entries: [(String, String, String?)] = [
    ("来週の MTG で PoC を見せる。", "えー、来週のMTGで、あのPoCを見せる", nil),
    ("llama-server を立てて、Silero で区間を切ってから認識する。", "llama-server を立てて、Silero で区間を切ってから認識する。", nil),
    ("明日、日和坂の研究室で会う", "明日、日和坂の研究室で会う", "推敲せずに貼りました（10 秒で答えませんでした）"),
    ("今日は天気が良いので、公園で子供と遊んだ。", "今日は天気が良いので、公園で子供と遊んだ。", nil),
]

/// ⌘N で語を足し、そのまま打った文字が新しい行の「書き方」に入るかを確かめて撮る。
@MainActor
func renderAdding() {
    let dictionary = FileManager.default.temporaryDirectory.appendingPathComponent("poko-render-adding.txt")
    try? Vocabulary.serialize(Array(terms.prefix(3))).write(to: dictionary, atomically: true, encoding: .utf8)
    setenv("POKO_DICTIONARY", dictionary.path, 1)
    let activity = Activity()
    activity.pane = .dictionary
    let store = VocabularyStore()
    let window = MainWindow.makeWindow(activity: activity, vocabulary: store)
    window.appearance = NSAppearance(named: .aqua)
    window.setFrame(NSRect(x: 80, y: 80, width: 520, height: 560), display: true)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    settle()
    func key(_ characters: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: window.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0)!
    }
    _ = window.performKeyEquivalent(with: key("n", .command))
    settle()
    for character in "SwiftUI" { NSApp.sendEvent(key(String(character))) }
    settle()
    print("⌘N のあと打った文字: 新しい行の書き方 = \"\(store.terms.last?.written ?? "(行がない)")\"（\(store.terms.count) 語）")
    let file = out.appendingPathComponent("dictionary-adding-light.png")
    let shot = Process()
    shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    shot.arguments = ["-x", "-o", "-l\(window.windowNumber)", file.path]
    try? shot.run()
    shot.waitUntilExit()
    window.orderOut(nil)
}

MainActor.assumeIsolated {
    renderAdding()
    for dark in [false, true] {
        let tone = dark ? "dark" : "light"
        render("history-empty-\(tone)", dark: dark, terms: [], pane: .history)
        render("history-\(tone)", dark: dark, terms: terms, pane: .history, phase: .listening, entries: entries)
        render("dictionary-empty-\(tone)", dark: dark, terms: [], pane: .dictionary)
        render("history-notice-\(tone)", dark: dark, terms: terms, pane: .history, entries: entries, notice: "聞き取れませんでした")
        render("dictionary-\(tone)", dark: dark, terms: terms, pane: .dictionary, entries: entries)
    }
}
print("描きました: \(out.path)")
