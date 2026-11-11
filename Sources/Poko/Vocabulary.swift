import Foundation

/// 辞書の1語。書き方と、その読み（ひらがなかカタカナ。いくつもあるときは「、」か「,」で区切る）。
struct Term: Identifiable, Equatable {
    var id = UUID()
    var written: String
    var readings: String

    static func == (a: Term, b: Term) -> Bool { a.written == b.written && a.readings == b.readings }

    /// 読みを1つずつに分けたもの。
    var readingList: [String] {
        readings.components(separatedBy: CharacterSet(charactersIn: ",、，"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var trimmedWritten: String { written.trimmingCharacters(in: .whitespaces) }
}

/// 辞書。固有名詞や略語を、書き方と読みの組で持つ。
///
/// 認識のときに speech.cpp の `--keywords`（Haas-ja-v1.0 の機能）へ渡すと、その読みに聞こえた所がこの書き方になる。
/// 推敲を使うときは、LLM にも用語集として渡す（漢字の名前のように、認識では効きにくいものを直させる）。
/// ファイルは1行に1語の「書き方=読み,読み」で、手でも直せる。`#` で始まる行と空の行は読み飛ばす。
enum Vocabulary {
    /// 置き場所。環境変数 `POKO_DICTIONARY` があればそのファイルを使う（テスト用）。
    static var file: URL {
        if let path = getenv("POKO_DICTIONARY") { return URL(fileURLWithPath: String(cString: path)) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Poko/dictionary.txt")
    }

    static let header = """
    # Poko の辞書。1行に1語、「書き方=読み」。読みがいくつもあるときは「,」で区切る。
    # 例: PoC=ぴーおーしー,ぽっく
    """

    static func parse(_ text: String) -> [Term] {
        text.components(separatedBy: .newlines).compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "＝", with: "=")
            if line.isEmpty || line.hasPrefix("#") { return nil }
            guard let equal = line.firstIndex(of: "=") else { return Term(written: line, readings: "") }
            // 読みは画面では「、」で区切って見せる（ファイルと speech.cpp には「,」で書く）。
            let readings = Term(written: "", readings: String(line[line.index(after: equal)...])).readingList
            return Term(written: String(line[..<equal]).trimmingCharacters(in: .whitespaces),
                        readings: readings.joined(separator: "、"))
        }
    }

    static func serialize(_ terms: [Term]) -> String {
        let lines = terms.compactMap(line)
        return ([header] + lines).joined(separator: "\n") + "\n"
    }

    /// speech.cpp の `--keywords` に渡す文字列。語がなければ nil（空や空白だけを渡すと認識が失敗するため）。
    static func keywords(_ terms: [Term]) -> String? {
        let lines = terms.compactMap(line)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// 推敲の指示に添える用語集（1行に「書き方（読み、読み）」）。語がなければ nil。
    static func glossary(_ terms: [Term]) -> String? {
        let lines = terms.compactMap { term -> String? in
            let written = clean(term.trimmedWritten)
            guard !written.isEmpty else { return nil }
            let readings = term.readingList
            return readings.isEmpty ? written : "\(written)（\(readings.joined(separator: "、"))）"
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// その語が思うように効かなそうなら、理由を返す（辞書の画面で ⚠︎ と一緒に出す）。
    /// どれも、合成音声で試したときに見えたこと。
    static func hint(for term: Term) -> String? {
        let written = term.trimmedWritten
        guard !written.isEmpty else { return nil }
        let readings = term.readingList
        if readings.isEmpty {
            return isKana(written) ? nil : "読みがないと、ほとんど効きません"
        }
        if readings.contains(where: { !isKana($0) }) {
            return "読みはひらがなかカタカナで書きます（ローマ字の読みでは、関係のない所が置き換わりました）"
        }
        if readings.contains(where: { $0.count <= 2 }) {
            return "読みが短いと、「もぐもぐ」のような普通の言葉の中でも置き換わることがあります"
        }
        if written.unicodeScalars.contains(where: isKanji) {
            return "漢字の語は、認識だけでは効きにくい語です。推敲を使うと直りやすくなります"
        }
        return nil
    }

    static func load() -> [Term] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return parse(text)
    }

    static func save(_ terms: [Term]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try serialize(terms).write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: 中身

    /// ファイルと `--keywords` での1行。書き方が空なら nil。
    private static func line(_ term: Term) -> String? {
        let written = clean(term.trimmedWritten)
        guard !written.isEmpty else { return nil }
        let readings = term.readingList.map(clean).filter { !$0.isEmpty }
        return readings.isEmpty ? written : "\(written)=\(readings.joined(separator: ","))"
    }

    /// 1行の形を壊す文字（改行と「=」、先頭の「#」）を除く。先頭が「#」だと、読み直したときにコメントになるため。
    private static func clean(_ text: String) -> String {
        let text = text.components(separatedBy: .newlines).joined()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "＝", with: "")
        return String(text.drop { $0 == "#" || $0 == " " })
    }

    private static func isKana(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { (0x3040...0x30FF).contains($0.value) }
    }

    private static func isKanji(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }
}

/// 窓と認識が共有する辞書。変えたらすぐファイルに書く。
@MainActor
final class VocabularyStore: ObservableObject {
    @Published var terms: [Term] { didSet { if terms != oldValue { write() } } }
    /// 書けなかったときの理由（窓に出す）。
    @Published private(set) var problem: String?

    init() {
        terms = Vocabulary.load()
    }

    /// ファイルを手で直したときのために、窓を開くたびに読み直す。
    func reload() {
        let loaded = Vocabulary.load()
        // 書きかけ（書き方がまだ空）の行は、ファイルにはないので残す。
        let drafts = terms.filter { $0.trimmedWritten.isEmpty }
        if loaded != terms.filter({ !$0.trimmedWritten.isEmpty }) { terms = loaded + drafts }
    }

    var keywords: String? { Vocabulary.keywords(terms) }

    private func write() {
        do {
            try Vocabulary.save(terms)
            problem = nil
        } catch {
            problem = "辞書を保存できません: \(error.localizedDescription)"
        }
    }
}
