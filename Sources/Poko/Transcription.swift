import Foundation

/// アプリが使うファイルの場所。Info.plist の `PokoHome`（ビルドしたフォルダ）か、環境変数 `POKO_HOME` から決める。
struct EngineFiles {
    let speech: URL
    let model: URL
    let vad: URL
    /// 推敲に使う llama.cpp と Gemma 4。`setup.sh --llm` で取ってくる。なくても認識はできる。
    let llamaServer: URL
    let gemma: URL

    static func locate() -> EngineFiles {
        let home = ProcessInfo.processInfo.environment["POKO_HOME"]
            ?? Bundle.main.object(forInfoDictionaryKey: "PokoHome") as? String
            ?? FileManager.default.currentDirectoryPath
        let root = URL(fileURLWithPath: home)
        return EngineFiles(
            speech: root.appendingPathComponent("vendor/speech"),
            model: root.appendingPathComponent("models/haas-ja-v1.0-q8_0.gguf"),
            vad: root.appendingPathComponent("models/silero-vad.gguf"),
            llamaServer: root.appendingPathComponent("vendor/llama/llama-server"),
            gemma: root.appendingPathComponent("models/gemma-4-E4B-it-Q4_K_M.gguf")
        )
    }

    /// 認識に要るファイルで足りないものがあれば、その説明を返す（推敲のものは含めない）。
    func missing() -> String? {
        for url in [speech, model, vad] where !FileManager.default.fileExists(atPath: url.path) {
            return "\(url.lastPathComponent) がありません。scripts/setup.sh を実行してください"
        }
        return nil
    }
}

/// 1回の録音につき `speech asr` を1つ動かす。
///
/// 押した時点で起動し、録りながら標準入力へ 16 kHz・16 bit の音を流す。speech.cpp は Silero VAD で
/// 話している区間を見つけるたびに、その区間を Haas で認識して1行書く。離したら標準入力を閉じ、
/// 最後の区間の結果を待つだけなので、長く話しても離してからの待ち時間は短い。
/// 書き込みと `writeFailed` は `writer` の直列キューの中でだけ触るので、どのスレッドから使ってもよい。
final class Transcription: @unchecked Sendable {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let sampleRate = 16000
    /// 離してから結果が出るまでの上限。3 分の音声でも普通は数秒で終わる。
    static let timeout: TimeInterval = 60
    /// 辞書をどれだけ強く効かせるか（speech.cpp の `--keywords-alpha`。speech.cpp の既定は 2）。
    /// 合成音声で試すと、2 では取りこぼしがあり、4 では辞書にない所まで辞書の語に変わった。
    static let keywordsAlpha = 3.0

    private let process = Process()
    private let input = Pipe()
    private let writer = DispatchQueue(label: "poko.transcription.writer")
    private var writeFailed = false
    private let output: Task<Data, Never>
    private let errors: Task<Data, Never>

    /// `keywords` は辞書（`Vocabulary.keywords`）。nil なら辞書なしで認識する。
    init(files: EngineFiles, keywords: String? = nil) throws {
        if let missing = files.missing() { throw Failure(message: missing) }
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = files.speech
        process.arguments = [
            "asr", files.model.path,
            "--vad", files.vad.path,
            "--rate", String(Self.sampleRate),
        ]
        if let keywords {
            process.arguments! += ["--keywords", keywords, "--keywords-alpha", String(Self.keywordsAlpha)]
        }
        process.arguments!.append("-")
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        // 結果とログは起動直後から読み続ける（読まずにいるとパイプが詰まり、speech が止まるため）。
        self.output = Task { await Self.readAll(output.fileHandleForReading) }
        self.errors = Task { await Self.readAll(errors.fileHandleForReading) }
        do {
            try process.run()
        } catch {
            throw Failure(message: "speech を起動できません: \(error.localizedDescription)")
        }
    }

    /// 録った音（16 bit・リトルエンディアン・モノラル）を渡す。どのスレッドから呼んでもよい。
    func feed(_ pcm: Data) {
        writer.async { [self] in
            guard !writeFailed else { return }
            do {
                try input.fileHandleForWriting.write(contentsOf: pcm)
            } catch {
                writeFailed = true  // speech が先に終わった。理由は finish() が stderr から拾う
            }
        }
    }

    /// 音を渡し終えたことを伝え、認識した文を返す。
    func finish() async throws -> String {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            writer.async { [self] in
                try? input.fileHandleForWriting.close()
                done.resume()
            }
        }
        let watchdog = DispatchWorkItem { [process] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout, execute: watchdog)
        defer { watchdog.cancel() }

        let text = String(decoding: await output.value, as: UTF8.self)
        let log = String(decoding: await errors.value, as: UTF8.self)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async { [process] in
                process.waitUntilExit()
                done.resume()
            }
        }
        // 3 は「モデルが書ける長さの上限で止まった」。そこまでの文は出ているので使う。
        guard process.terminationReason == .exit, [0, 3].contains(process.terminationStatus) else {
            throw Failure(message: Self.reason(from: log) ?? "認識できませんでした（終了コード \(process.terminationStatus)）")
        }
        return Transcript.join(output: text)
    }

    /// 録った音を捨てる。
    func cancel() {
        writer.async { [self] in
            try? input.fileHandleForWriting.close()
        }
        if process.isRunning { process.terminate() }
    }

    /// 起動時の準備運動。0.5 秒の小さな雑音を VAD なしで認識させ、Haas を一度動かす。
    /// Metal のカーネルは初めて動かすときに用意される（初めての Mac や OS の更新後は十数秒）ので、
    /// 最初に話す前に済ませておく。無音を VAD 付きで渡すと区間が見つからず、Haas が動かないため、こうする。
    static func warmUp(files: EngineFiles) async throws {
        if let missing = files.missing() { throw Failure(message: missing) }
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("poko-warmup.wav")
        var generator = SystemRandomNumberGenerator()
        let samples = (0..<sampleRate / 2).map { _ in Int16.random(in: -64...64, using: &generator) }
        try Self.wav(samples).write(to: wav)
        defer { try? FileManager.default.removeItem(at: wav) }

        let process = Process()
        process.executableURL = files.speech
        process.arguments = ["asr", files.model.path, wav.path]
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let log = String(decoding: await readAll(errors.fileHandleForReading), as: UTF8.self)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                done.resume()
            }
        }
        guard process.terminationStatus == 0 else {
            throw Failure(message: reason(from: log) ?? "speech.cpp を動かせません（終了コード \(process.terminationStatus)）")
        }
    }

    /// 16 kHz・16 bit・モノラルの WAV を作る。
    static func wav(_ samples: [Int16]) -> Data {
        func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        let body = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        var data = Data("RIFF".utf8) + le(UInt32(36 + body.count)) + Data("WAVEfmt ".utf8)
        data += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(1))
        data += le(UInt32(sampleRate)) + le(UInt32(sampleRate * 2)) + le(UInt16(2)) + le(UInt16(16))
        data += Data("data".utf8) + le(UInt32(body.count)) + body
        return data
    }

    /// speech は失敗の理由を「speech: 分類: 説明」の1行で stderr に書く。
    private static func reason(from log: String) -> String? {
        log.components(separatedBy: .newlines)
            .last { $0.hasPrefix("speech:") }
            .map { String($0.dropFirst("speech:".count)).trimmingCharacters(in: .whitespaces) }
    }

    private static func readAll(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { done in
            DispatchQueue.global().async {
                done.resume(returning: handle.readDataToEndOfFile())
            }
        }
    }
}
