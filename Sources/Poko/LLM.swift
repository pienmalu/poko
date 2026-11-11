import Foundation

// 文字の LLM を呼ぶ口。Mac の中の Gemma（llama-server）か、ログイン済みの Claude Code・Codex の CLI を使う。
// アプリは API キーもトークンも持たない。サブスクを使うときは、公式の CLI にそのまま頼む。
// Poko のほかのファイルに頼らないので、別のアプリからもこのファイルだけを持ち込んで使える。

/// どこで考えるか。
enum LLMProvider: String, CaseIterable {
    /// Mac の中の Gemma 4。文字は外に出ない。
    case local
    /// Claude Code（`claude -p`）。文字を Anthropic に送る。
    case claude
    /// Codex（`codex exec`）。文字を OpenAI に送る。
    case chatgpt

    /// 文字を Mac の外に送るか。
    var sendsOut: Bool { self != .local }
}

struct LLMFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Mac の中（llama-server）

/// llama-server を、使うときだけ起動する。しばらく使わなければ止め、メモリを返す。
/// Mogu の推敲（LLMServer）から持ってきて、モデルとフォルダを外から渡す形にした。
@MainActor
final class LocalLLM {
    /// 最後に使ってから止めるまで。起動は話している間に済むので、短めにしてメモリを早く返す。
    var idleLimit: TimeInterval = 2 * 60
    /// モデルに渡せる長さ（トークン）。短い文しか扱わないので小さくし、メモリを抑える。
    var contextTokens = 4096
    /// 起動を待つ上限。初めての Mac や OS の更新後は、Metal の準備で十数秒かかる。
    var startupLimit: TimeInterval = 25

    let server: URL
    let model: URL

    private var process: Process?
    private var port = 0
    private var idleTimer: Timer?
    /// health が ok を返した後だけ true。
    private var ready = false
    private var starting: Task<URL, Error>?
    private let pidFile: URL

    /// - Parameters:
    ///   - server: `llama-server` の場所
    ///   - model: `.gguf` の場所
    ///   - name: 落ちたときに残ったサーバーを片付けるための記録の名前（アプリごとに分ける）
    init(server: URL, model: URL, name: String) {
        self.server = server
        self.model = model
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        pidFile = caches.appendingPathComponent("llama-server.pid")
        killOrphan()
    }

    /// 足りないファイルがあれば、その説明を返す。
    func missing() -> String? {
        if !FileManager.default.isExecutableFile(atPath: server.path) { return "llama.cpp がありません" }
        if !FileManager.default.fileExists(atPath: model.path) { return "\(model.lastPathComponent) がありません" }
        return nil
    }

    /// 先に起動しておく（待たない）。使う少し前に呼ぶと、使うときに読み込みを待たずに済む。
    func prepare() {
        guard missing() == nil else { return }
        Task { _ = try? await endpoint() }
    }

    /// 起動していなければ起動し、受け付けられるまで待つ。返すのは API の入口。
    func endpoint() async throws -> URL {
        if let process, process.isRunning, ready {
            touch()
            return URL(string: "http://127.0.0.1:\(port)")!
        }
        if let starting { return try await starting.value }  // 起動の途中なら、その完了を待つ
        stop()
        if let missing = missing() { throw LLMFailure(message: missing) }

        port = Self.freePort()
        let task = Process()
        task.executableURL = server
        task.arguments = ["-m", model.path, "--host", "127.0.0.1", "--port", "\(port)",
                          "-c", "\(contextTokens)", "-ngl", "99", "--jinja", "--parallel", "1", "--no-webui"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            throw LLMFailure(message: "llama-server を起動できません: \(error.localizedDescription)")
        }
        process = task
        try? "\(task.processIdentifier)".write(to: pidFile, atomically: true, encoding: .utf8)

        let base = URL(string: "http://127.0.0.1:\(port)")!
        let waiting = Task<URL, Error> {
            let deadline = Date().addingTimeInterval(startupLimit)
            while Date() < deadline {
                guard task.isRunning else { throw LLMFailure(message: "llama-server が終了しました") }
                if let (data, _) = try? await URLSession.shared.data(from: base.appendingPathComponent("health")),
                   String(decoding: data, as: UTF8.self).contains("ok") {
                    return base
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            throw LLMFailure(message: "llama-server が時間内に応答しませんでした")
        }
        starting = waiting
        do {
            let url = try await waiting.value
            starting = nil
            guard process === task else { throw LLMFailure(message: "llama-server が途中で止められました") }
            ready = true
            touch()
            return url
        } catch {
            starting = nil
            if process === task { stop() }
            throw error
        }
    }

    /// 1回だけ頼んで、答えを全部返す。
    func complete(system: String, user: String, temperature: Double = 0) async throws -> String {
        let base = try await endpoint()
        var request = URLRequest(url: base.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": temperature,
            "chat_template_kwargs": ["enable_thinking": false],
        ] as [String: Any])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        touch()
        guard status == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (json["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMFailure(message: "Gemma から答えを受け取れませんでした（HTTP \(status)）")
        }
        guard choice["finish_reason"] as? String == "stop" else {
            throw LLMFailure(message: "Gemma の答えが途中で切れました")
        }
        return content
    }

    /// 答えを書いた分だけ少しずつ渡しながら頼み、最後に全部を返す。
    /// onPartial には、それまでに書かれた全文を渡す（このメインスレッドの上で呼ぶ）。
    func stream(system: String, user: String, temperature: Double = 0.3,
                onPartial: @MainActor (String) -> Void) async throws -> String {
        let base = try await endpoint()
        var request = URLRequest(url: base.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": temperature,
            "stream": true,
            "chat_template_kwargs": ["enable_thinking": false],
        ] as [String: Any])
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var body = ""
            for try await line in bytes.lines { body += line }
            throw LLMFailure(message: body.contains("context") || body.contains("exceed")
                             ? "Gemma に渡す文が長すぎます（\(contextTokens) トークンまで）"
                             : "Gemma から答えを受け取れませんでした（HTTP \(status)）")
        }
        var output = ""
        var finish: String?
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data: ") else { continue }
            let payload = line.dropFirst(6)
            if payload == "[DONE]" { break }
            guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                  let choice = (json["choices"] as? [[String: Any]])?.first else { continue }
            if let reason = choice["finish_reason"] as? String { finish = reason }
            if let delta = choice["delta"] as? [String: Any], let piece = delta["content"] as? String {
                output += piece
                onPartial(output)
            }
        }
        touch()
        guard finish == "stop" else { throw LLMFailure(message: "Gemma の答えが途中で切れました") }
        return output
    }

    func stop() {
        idleTimer?.invalidate()
        starting?.cancel()
        starting = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        ready = false
        try? FileManager.default.removeItem(at: pidFile)
    }

    private func touch() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleLimit, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    /// 前回アプリが落ちて、サーバーだけが残っていたら止める。
    private func killOrphan() {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        var buffer = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0,
           String(cString: buffer).hasSuffix("llama-server") {
            kill(pid, SIGTERM)
        }
        try? FileManager.default.removeItem(at: pidFile)
    }

    /// 空いている番号を OS に選ばせる。
    private static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        let port = Int(UInt16(bigEndian: address.sin_port))
        return port == 0 ? 18412 : port
    }
}

// MARK: - サブスク（ログイン済みの CLI）

/// Claude Code と Codex の CLI を、1回ごとに起動して使う。
/// どちらも先にターミナルでログインしておく（`claude` を一度開く、`codex login`）。
enum SubscriptionLLM {
    /// 使うモデル。変えたいときはここを直す。
    static let claudeModel = "sonnet"
    static let codexModel = "gpt-6-luna"
    static let codexEffort = "none"

    /// CLI の場所。`defaults write <アプリの ID> claudePath /path/to/claude` のように書けば、そちらを使う。
    /// Dock から開いたアプリにはシェルの PATH が渡らないので、ターミナルと同じものを使うよう、
    /// ログインシェルに一度だけ尋ねる（nvm は .zshrc で読まれるので、対話モードで開く）。
    /// 答えがなければ、よくある場所を探す。
    static func locate(_ provider: LLMProvider) -> URL? {
        let name = provider == .claude ? "claude" : "codex"
        if let custom = UserDefaults.standard.string(forKey: "\(name)Path"), !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        lock.lock()
        defer { lock.unlock() }
        if let found = found[name] { return found }
        let url = askShell(name) ?? searchCommonPlaces(name)
        found[name] = url
        return url
    }

    private static let lock = NSLock()
    private static var found: [String: URL?] = [:]

    /// ログインシェルで `command -v` を実行し、出てきた場所を返す。3 秒で諦める。
    private static func askShell(_ name: String) -> URL? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lic", "command -v \(name)"]
        let output = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        let path = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
            .last { $0.hasPrefix("/") }
        guard let path, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func searchCommonPlaces(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "\(home)/.local/bin/\(name)"]
        if name == "claude" { candidates.append("\(home)/.claude/local/claude") }
        // nvm で入れた node の下（新しい版から）
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            for version in versions.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }) {
                candidates.append("\(nvm)/\(version)/bin/\(name)")
            }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    /// CLI に渡す引数。純粋な関数にしてテストする。
    /// `stream` が true なら、claude は書いた分だけ JSON の行で返す（codex は最後にまとめて返すだけ）。
    static func arguments(for provider: LLMProvider, system: String, user: String, stream: Bool = false) -> [String] {
        switch provider {
        case .claude:
            // ツール、設定、MCP、スキル、会話の保存を使わず、答えるだけにする。
            // --bare はサブスクのログインを読まないので使わない。
            var args = ["-p", "--model", claudeModel, "--tools", "", "--setting-sources", "",
                        "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence"]
            if stream { args += ["--output-format", "stream-json", "--include-partial-messages", "--verbose"] }
            return args + ["--system-prompt", system, user]
        case .chatgpt:
            // 設定と規則を読まず、読み取り専用で、会話を残さない。指示と本文は1つのプロンプトにまとめる。
            return ["exec", "--skip-git-repo-check", "--ephemeral", "--ignore-user-config", "--ignore-rules",
                    "-s", "read-only", "-m", codexModel, "-c", "model_reasoning_effort=\"\(codexEffort)\"",
                    "--color", "never", system + "\n\n" + user]
        case .local:
            return []
        }
    }

    /// 1回だけ頼んで、答えを全部返す。`timeout` 秒で打ち切る。呼んだ Task を取り消すと、CLI も止める。
    /// onPartial を渡すと、それまでに書かれた全文を少しずつ渡す（claude だけ。codex は最後に1回）。どのスレッドから呼ぶかは決まっていない。
    static func complete(_ provider: LLMProvider, system: String, user: String, timeout: TimeInterval,
                         onPartial: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let streaming = onPartial != nil && provider == .claude
        let name = provider == .claude ? "Claude Code（claude）" : "Codex（codex）"
        guard let executable = locate(provider) else {
            throw LLMFailure(message: "\(name) が見つかりません")
        }
        // 何もない一時フォルダで動かす（プロジェクトの指示を読ませず、ファイルにも触れさせない）。
        let workdir = FileManager.default.temporaryDirectory.appendingPathComponent("llm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workdir) }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments(for: provider, system: system, user: user, stream: streaming)
        process.currentDirectoryURL = workdir
        var environment = ProcessInfo.processInfo.environment
        // codex は node で動くので、node のあるフォルダ（codex と同じフォルダ）を PATH に入れる。
        let folder = executable.resolvingSymlinksInPath().deletingLastPathComponent().path
        let linked = executable.deletingLastPathComponent().path
        environment["PATH"] = [linked, folder, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            .joined(separator: ":")
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw LLMFailure(message: "\(name) を起動できません: \(error.localizedDescription)")
        }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer { watchdog.cancel() }

        let parser = StreamParser()
        let (out, err) = await withTaskCancellationHandler {
            async let text = readAll(output.fileHandleForReading) { line in
                guard streaming, let partial = parser.feed(line) else { return }
                onPartial?(partial)
            }
            async let log = readAll(errors.fileHandleForReading)
            let result = await (text, log)
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async {
                    process.waitUntilExit()
                    done.resume()
                }
            }
            return result
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            if process.terminationReason == .uncaughtSignal {
                throw LLMFailure(message: "\(name) が \(Int(timeout)) 秒で答えませんでした")
            }
            let last = String(decoding: err.isEmpty ? out : err, as: UTF8.self)
                .components(separatedBy: .newlines).last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            throw LLMFailure(message: "\(name) が失敗しました: \(last.prefix(120))")
        }
        if streaming {
            guard let result = parser.result else { throw LLMFailure(message: "\(name) の答えを読めませんでした") }
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let text = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        onPartial?(text)
        return text
    }

    /// claude の stream-json を1行ずつ読み、書かれた文を積み上げる。
    final class StreamParser: @unchecked Sendable {
        private(set) var text = ""
        /// 最後に届く result の行の本文。
        private(set) var result: String?

        /// 文が増えたら、それまでの全文を返す。
        func feed(_ line: String) -> String? {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
            switch json["type"] as? String {
            case "stream_event":
                guard let event = json["event"] as? [String: Any],
                      let delta = event["delta"] as? [String: Any],
                      delta["type"] as? String == "text_delta",
                      let piece = delta["text"] as? String else { return nil }
                text += piece
                return text
            case "result":
                result = json["result"] as? String
                return nil
            default:
                return nil
            }
        }
    }

    /// 終わりまで読む。onLine を渡すと、1行届くたびに呼ぶ。
    private static func readAll(_ handle: FileHandle, onLine: ((String) -> Void)? = nil) async -> Data {
        await withCheckedContinuation { done in
            DispatchQueue.global().async {
                guard let onLine else { return done.resume(returning: handle.readDataToEndOfFile()) }
                var all = Data()
                var pending = Data()
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    all.append(chunk)
                    pending.append(chunk)
                    while let newline = pending.firstIndex(of: 0x0A) {
                        onLine(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
                        pending.removeSubrange(pending.startIndex...newline)
                    }
                }
                if !pending.isEmpty { onLine(String(decoding: pending, as: UTF8.self)) }
                done.resume(returning: all)
            }
        }
    }
}
