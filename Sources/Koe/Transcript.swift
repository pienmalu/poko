import Foundation

/// speech.cpp が区間ごとに1行ずつ書く結果を、貼り付ける1つの文にまとめる。
enum Transcript {
    /// 区間の終わりに句読点がなければ「、」でつなぐ。
    /// 区間は 0.5 秒以上の無音で切れる。言いよどみ（「えーと…」）でも切れるので、「。」ではなく「、」にしておく。
    static func join(_ lines: [String]) -> String {
        let parts = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var text = ""
        for part in parts {
            if let last = text.last, !endsClause(last) {
                text += "、"
            }
            text += part
        }
        return text
    }

    static func join(output: String) -> String {
        join(output.components(separatedBy: .newlines))
    }

    private static func endsClause(_ character: Character) -> Bool {
        "。、．，！？!?,.…」』）)".contains(character)
    }
}
