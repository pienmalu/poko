import AppKit

/// 文字を、いま前にあるアプリのカーソル位置に貼る。
///
/// クリップボードに入れて ⌘V を送り、少し待ってから元の中身に戻す。
/// クリップボード履歴のアプリには残らないよう、一時的な中身であることを示す型も付ける。
@MainActor
enum Paster {
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let restoreDelay: TimeInterval = 0.5

    static func paste(_ text: String) {
        let board = NSPasteboard.general
        let saved = snapshot(of: board)

        board.clearContents()
        board.setString(text, forType: .string)
        board.setData(Data(), forType: transient)
        let ours = board.changeCount

        sendCommandV()

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            guard board.changeCount == ours else { return }  // その間に別の何かがコピーされた
            board.clearContents()
            if !saved.isEmpty { board.writeObjects(saved) }
        }
    }

    /// クリップボードの中身を、型ごとに写し取る。
    private static func snapshot(of board: NSPasteboard) -> [NSPasteboardItem] {
        (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    /// ⌘V を送る。修飾キーは ⌘ だけにする（押していた右⌘の状態を引きずらないため）。
    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9  // kVK_ANSI_V（JIS 配列でも同じ位置）
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
