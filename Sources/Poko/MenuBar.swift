import AppKit

/// メニューバーの項目。アイコンを動かし、メニューを出す。窓は出さない。
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    struct Actions {
        var chooseKey: (TriggerKey) -> Void
        var copyLast: () -> Void
        var allowAccessibility: () -> Void
        var allowMicrophone: () -> Void
    }

    // どれも、値が変わったときだけメニューを作り直す（許可を待つ間に毎秒作り直すと、押そうとした項目が消えるため）。
    /// メニューの先頭に出す1行（いまの状態か、直近の失敗の理由）。
    var status = "" { didSet { if status != oldValue { refreshMenu() } } }
    var key: TriggerKey = .rightCommand { didSet { if key != oldValue { refreshMenu() } } }
    var lastText: String? { didSet { if lastText != oldValue { refreshMenu() } } }
    var needsAccessibility = false { didSet { if needsAccessibility != oldValue { refreshMenu() } } }
    var needsMicrophone = false { didSet { if needsMicrophone != oldValue { refreshMenu() } } }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let actions: Actions
    private var motion = IconMotion()
    private var timer: Timer?
    private let clock = Date()
    private var errorTimer: Timer?
    private var hideOnClose = false

    init(actions: Actions) {
        self.actions = actions
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false  // 「最後の結果をコピー」の有効・無効を自分で決める
        item.menu = menu
        item.button?.setAccessibilityLabel("Poko")
        show(.idle)
        refreshMenu()
    }

    // MARK: アイコン

    /// 何もしていないときの形（`.idle` か、準備ができていなければ `.unready`）。
    var resting: IconMode = .idle {
        didSet { if mode == .idle || mode == .unready { show(resting) } }
    }

    func show(_ mode: IconMode, pop: Bool = false) {
        errorTimer?.invalidate()
        motion.set(mode, at: now, pop: pop)
        if mode == .error {
            // 失敗の印は少し見せてから、待っている形に戻す（理由はメニューに残る）。
            errorTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.settle() }
            }
        }
        animate()
    }

    /// 待っている形に戻す。
    func settle(pop: Bool = false) {
        show(resting, pop: pop)
    }

    var mode: IconMode { motion.mode }

    func hear(_ level: Float) {
        motion.hear(level)
    }

    private var now: TimeInterval { Date().timeIntervalSince(clock) }

    private func animate() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)  // メニューを開いている間も動かす
        self.timer = timer
        tick()
    }

    private func tick() {
        let moving = motion.advance(by: 1.0 / 60, at: now)
        item.button?.image = IconDrawing.image(heights: motion.heights, mode: motion.mode)
        if !moving {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: メニュー

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenu()
    }

    /// メニューを開く（Dock のアイコンを押したとき）。
    /// 閉じたら Poko を隠して、前のアプリに戻す。Poko が前に残ると、次に話した文の貼り先がなくなるため。
    func open() {
        hideOnClose = true
        item.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard hideOnClose else { return }
        hideOnClose = false
        NSApp.hide(nil)
    }

    private func refreshMenu() {
        menu.removeAllItems()
        menu.addItem(disabled(status.isEmpty ? "\(key.label) を押しながら話す" : status))

        if needsAccessibility {
            menu.addItem(button("アクセシビリティを許可…") { [actions] in actions.allowAccessibility() })
        }
        if needsMicrophone {
            menu.addItem(button("マイクを許可…") { [actions] in actions.allowMicrophone() })
        }
        menu.addItem(.separator())

        let keys = NSMenu()
        for choice in TriggerKey.allCases {
            let entry = button(choice.label) { [actions] in actions.chooseKey(choice) }
            entry.state = choice == key ? .on : .off
            keys.addItem(entry)
        }
        let keysItem = NSMenuItem(title: "キー", action: nil, keyEquivalent: "")
        keysItem.submenu = keys
        menu.addItem(keysItem)

        let copy = button("最後の結果をコピー") { [actions] in actions.copyLast() }
        copy.isEnabled = lastText != nil
        if let lastText { copy.toolTip = lastText }
        menu.addItem(copy)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Poko を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    private func button(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        let target = MenuAction(handler)
        entry.target = target
        entry.representedObject = target  // メニュー項目が target を持ち続けるように
        return entry
    }
}

/// メニュー項目からクロージャを呼ぶための小さな受け手。
private final class MenuAction: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run() { handler() }
}
