import AppKit

/// Poko: キーを押しながら話すと、離したときにカーソル位置へ文字が入る。
/// 音声は Mac の外に出さない。文字を外に送るのは、推敲に Claude か ChatGPT を選んだときだけ。
@main
enum PokoMain {
    static func main() {
        signal(SIGPIPE, SIG_IGN)  // speech が先に終わっても、書き込み側のこのアプリは落ちないように
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)  // Dock にも出す（窓は出さない）
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var poko: Poko?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.mainMenu()
        poko = Poko()
        poko?.launch()
        // 窓がないので、起動したら隠して前のアプリに戻す（前に残ると、話した文の貼り先がなくなる）。
        DispatchQueue.main.async { NSApp.hide(nil) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        poko?.shutDown()  // 推敲の llama-server を残さない
    }

    /// Dock のアイコンを押したときは、メニューバーのメニューを開く。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        poko?.openMenu()
        return false
    }

    /// Poko が前に出ている間の、画面上端のメニュー（⌘Q と ⌘H が効くように）。
    private static func mainMenu() -> NSMenu {
        let app = NSMenu()
        app.addItem(withTitle: "Poko を隠す", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "Poko を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let holder = NSMenuItem(title: "Poko", action: nil, keyEquivalent: "")
        holder.submenu = app
        let main = NSMenu()
        main.addItem(holder)
        return main
    }
}

/// 部品をつなぐ。キー → 録音 → 認識 → 貼り付け。
@MainActor
final class Poko {
    /// 1回に録れる長さ。達したら、離すのを待たずに認識する。
    static let longest: TimeInterval = 180
    /// 離してから録り続ける長さ。
    static let tail: TimeInterval = 0.2

    private let files = EngineFiles.locate()
    private let recorder = Recorder()
    private var flow = PushToTalk()
    private var session: Transcription?
    private var limit: Timer?
    private var permissionWatch: Timer?
    private var warmTimer: Timer?
    private lazy var polisher = Polisher(files: files)
    private var menuBar: MenuBar!
    private var hotKey: HotKey!

    private static let keySetting = "triggerKey"

    func launch() {
        let key = UserDefaults.standard.string(forKey: Self.keySetting).flatMap(TriggerKey.init) ?? .rightCommand
        menuBar = MenuBar(actions: .init(
            chooseKey: { [weak self] in self?.choose($0) },
            copyLast: { [weak self] in self?.copyLast() },
            copyRaw: { [weak self] in self?.copyRaw() },
            choosePolish: { [weak self] in self?.choose($0) },
            allowAccessibility: { Permissions.askForAccessibility(); Permissions.openAccessibilitySettings() },
            allowMicrophone: { Permissions.openMicrophoneSettings() }
        ))
        menuBar.key = key
        menuBar.polish = PolishMode.current
        hotKey = HotKey(key: key) { [weak self] in self?.handle($0) }
        hotKey.start()

        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.menuBar.hear(level) } }
        }

        if !Permissions.accessibility { Permissions.askForAccessibility() }
        Task {
            _ = await Permissions.askForMicrophone()
            refreshReadiness()
        }
        refreshReadiness()
        warmUp()
        // サブスクの CLI の場所を、使う前に裏で調べておく（ログインシェルに尋ねるので 0.5 秒ほどかかる）。
        if let provider = PolishMode.current.provider, provider.sendsOut {
            DispatchQueue.global().async { _ = SubscriptionLLM.locate(provider) }
        }
    }

    // MARK: 押す・離す

    private func handle(_ event: PushToTalk.Event) {
        switch flow.handle(event) {
        case .start: start()
        case .cancel: cancel()
        case .finish: finish()
        case nil: break
        }
    }

    private func start() {
        if let problem = readinessProblem() {
            flow.reset()
            fail(problem)
            return
        }
        do {
            let session = try Transcription(files: files)
            recorder.onAudio = { pcm in session.feed(pcm) }
            do {
                try recorder.start()
            } catch {
                session.cancel()
                throw error
            }
            self.session = session
        } catch {
            flow.reset()
            fail(error.localizedDescription)
            return
        }
        menuBar.status = "聴いています…"
        menuBar.show(.recording)
        limit = Timer.scheduledTimer(withTimeInterval: Self.longest, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.handle(.timeLimit) }
        }
        // 押し間違い（すぐ離す、右⌘+C など）でなさそうになってから、推敲の Gemma を読み込み始める。
        // 押すたびに 5 GB を読まないように。読み込みは話している間に済む。
        warmTimer = Timer.scheduledTimer(withTimeInterval: PushToTalk.minimumHold, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, case .recording = self.flow.state else { return }
                self.polisher.prepare()
            }
        }
    }

    private func cancel() {
        stopRecording()
        session?.cancel()
        session = nil
        menuBar.status = ""
        menuBar.settle()
    }

    private func finish() {
        limit?.invalidate()
        limit = nil
        guard let session else {
            stopRecording()
            flow.reset()
            return
        }
        self.session = nil
        menuBar.status = "文字にしています…"
        menuBar.show(.transcribing)
        Task {
            // 離してからも少しだけ録り続ける（言い終わりと同時に離しても語尾が切れないように）。
            try? await Task.sleep(for: .seconds(Self.tail))
            stopRecording()
            do {
                let raw = try await session.finish()
                // 推敲が終わって貼るまでは次を録らない（貼る順番が入れ替わらないように）。
                var text = raw
                var note: String?
                if !raw.isEmpty, polisher.mode != .off {
                    menuBar.status = "整えています…"
                    (text, note) = await polisher.polish(raw)
                }
                _ = flow.handle(.finished)
                if text.isEmpty {
                    menuBar.status = "聞き取れませんでした"
                    menuBar.settle()
                } else {
                    Paster.paste(text)
                    menuBar.lastText = text
                    menuBar.lastRaw = raw
                    menuBar.status = note ?? ""
                    menuBar.settle(pop: true)
                }
            } catch {
                _ = flow.handle(.finished)
                fail(error.localizedDescription)
            }
        }
    }

    private func stopRecording() {
        limit?.invalidate()
        limit = nil
        warmTimer?.invalidate()
        warmTimer = nil
        recorder.stop()
        recorder.onAudio = nil
    }

    private func fail(_ message: String) {
        menuBar.status = message
        menuBar.show(.error)
        NSSound.beep()
    }

    // MARK: 準備

    /// 押したときに足りないものがあれば、その説明を返す。
    private func readinessProblem() -> String? {
        if let missing = files.missing() { return missing }
        if !Permissions.accessibility { return "アクセシビリティの許可が必要です" }
        if Permissions.microphone != .authorized { return "マイクの許可が必要です" }
        return nil
    }

    /// 許可の状態をメニューとアイコンに映す。足りない間は1秒ごとに見直す。
    private func refreshReadiness() {
        let hadAccessibility = !menuBar.needsAccessibility
        menuBar.needsAccessibility = !Permissions.accessibility
        menuBar.needsMicrophone = Permissions.microphone != .authorized
        if !hadAccessibility && Permissions.accessibility {
            hotKey.start()  // 許可される前に付けた監視には何も届かないので、付け直す
        }
        let problem = readinessProblem()
        menuBar.resting = problem == nil ? .idle : .unready
        if let problem, menuBar.mode != .error, flow.state == .idle {
            menuBar.status = problem
        } else if problem == nil, menuBar.status.hasSuffix("が必要です") {
            menuBar.status = ""
        }

        permissionWatch?.invalidate()
        permissionWatch = nil
        if menuBar.needsAccessibility || menuBar.needsMicrophone {
            permissionWatch = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshReadiness() }
            }
        }
    }

    /// 起動時に一度 speech.cpp を動かし、Metal の準備（初回だけ十数秒）を最初に話す前に済ませる。
    private func warmUp() {
        guard files.missing() == nil else { return }  // 足りないことは refreshReadiness が伝える
        Task {
            do {
                try await Transcription.warmUp(files: files)
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    // MARK: メニュー

    private func choose(_ key: TriggerKey) {
        UserDefaults.standard.set(key.rawValue, forKey: Self.keySetting)
        hotKey.key = key
        menuBar.key = key
    }

    /// メニューバーのメニューを開く（Dock のアイコンを押したとき）。
    func openMenu() {
        menuBar.open()
    }

    private func choose(_ mode: PolishMode) {
        PolishMode.current = mode
        menuBar.polish = mode
        if mode != .local { polisher.stop() }
        if let problem = polisher.problem() {
            fail(problem)
        } else if menuBar.status.hasPrefix("推敲") {
            menuBar.status = ""
        }
    }

    func shutDown() {
        polisher.stop()
    }

    private func copyLast() {
        copy(menuBar.lastText)
    }

    private func copyRaw() {
        copy(menuBar.lastRaw)
    }

    private func copy(_ text: String?) {
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
