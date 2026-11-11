import AppKit

/// Poko: キーを押しながら話すと、離したときにカーソル位置へ文字が入る。音声は Mac の外に出ない。
@main
enum PokoMain {
    static func main() {
        signal(SIGPIPE, SIG_IGN)  // speech が先に終わっても、書き込み側のこのアプリは落ちないように
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // Dock に出さない
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var poko: Poko?

    func applicationDidFinishLaunching(_ notification: Notification) {
        poko = Poko()
        poko?.launch()
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
    private var menuBar: MenuBar!
    private var hotKey: HotKey!

    private static let keySetting = "triggerKey"

    func launch() {
        let key = UserDefaults.standard.string(forKey: Self.keySetting).flatMap(TriggerKey.init) ?? .rightCommand
        menuBar = MenuBar(actions: .init(
            chooseKey: { [weak self] in self?.choose($0) },
            copyLast: { [weak self] in self?.copyLast() },
            allowAccessibility: { Permissions.askForAccessibility(); Permissions.openAccessibilitySettings() },
            allowMicrophone: { Permissions.openMicrophoneSettings() }
        ))
        menuBar.key = key
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
                let text = try await session.finish()
                _ = flow.handle(.finished)
                if text.isEmpty {
                    menuBar.status = "聞き取れませんでした"
                    menuBar.settle()
                } else {
                    Paster.paste(text)
                    menuBar.lastText = text
                    menuBar.status = ""
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

    private func copyLast() {
        guard let text = menuBar.lastText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
