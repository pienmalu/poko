import AppKit

/// 押しながら話すキー。修飾キー単独の押し離しを見るので、Carbon のホットキーではなくイベントの監視を使う。
enum TriggerKey: String, CaseIterable {
    case rightCommand
    case fn

    var label: String {
        switch self {
        case .rightCommand: "右⌘"
        case .fn: "fn"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightCommand: 54  // kVK_RightCommand
        case .fn: 63            // kVK_Function
        }
    }

    func isDown(_ flags: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .rightCommand: flags.rawValue & 0x10 != 0  // NX_DEVICERCMDKEYMASK（右の ⌘ だけ）
        case .fn: flags.contains(.function)
        }
    }
}

/// どのアプリを使っていてもキーの押し離しを受け取る。アクセシビリティの許可が要る。
@MainActor
final class HotKey {
    var key: TriggerKey {
        didSet { isDown = false }
    }
    private let onEvent: (PushToTalk.Event) -> Void
    private var monitors: [Any] = []
    private var isDown = false

    /// クリックは見ない（押しながらクリックで入力欄を選んで話す、という使い方を捨てないため）。
    private static let watched: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]

    init(key: TriggerKey, onEvent: @escaping (PushToTalk.Event) -> Void) {
        self.key = key
        self.onEvent = onEvent
    }

    /// 監視を付け直す。アクセシビリティを許可した後にも呼ぶ（許可の前に付けた監視には何も届かないため）。
    func start() {
        stop()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: Self.watched, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: Self.watched, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        isDown = false
    }

    private func handle(_ event: NSEvent) {
        if event.type == .flagsChanged, event.keyCode == key.keyCode {
            let down = key.isDown(event.modifierFlags)
            guard down != isDown else { return }
            isDown = down
            onEvent(down ? .keyDown(at: event.timestamp) : .keyUp(at: event.timestamp))
        } else if isDown {
            onEvent(.otherInput)  // 押している間の別のキーは、ショートカットの一部
        }
    }
}
