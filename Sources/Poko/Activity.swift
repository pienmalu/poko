import Foundation

/// 窓に出すもの。いまの状態と、このアプリを起動してからの認識結果（ディスクには書かない）。
@MainActor
final class Activity: ObservableObject {
    enum Phase { case idle, listening, transcribing, polishing }
    enum Pane: String { case history, dictionary }

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let text: String
        /// 推敲する前の文（推敲で変わったときだけ）。
        let raw: String?
        /// 推敲できなかったときなどの一言。
        let note: String?
    }

    /// 覚えておく数。古いものから消す。
    static let limit = 200

    @Published var phase: Phase = .idle
    @Published private(set) var entries: [Entry] = []  // 新しいものが先
    @Published var pane: Pane = .history
    @Published var keyLabel = TriggerKey.rightCommand.label
    /// 直近の録音が文にならなかった理由（失敗、聞き取れなかった）。次に話し始めたら消す。
    @Published var notice: String?

    func add(text: String, raw: String, note: String?, at date: Date = Date()) {
        notice = nil
        entries.insert(Entry(date: date, text: text, raw: raw == text ? nil : raw, note: note), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    func remove(_ id: Entry.ID) {
        entries.removeAll { $0.id == id }
    }

    func removeAll() {
        entries.removeAll()
    }
}
