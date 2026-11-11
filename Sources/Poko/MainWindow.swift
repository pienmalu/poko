import AppKit
import SwiftUI

/// Poko の窓。「履歴」（話した文）と「辞書」（固有名詞や略語）の2つだけ。
/// 閉じたら Poko を隠して、前のアプリに戻す（Poko が前に残ると、話した文の貼り先がなくなるため）。
@MainActor
final class MainWindow: NSObject, NSWindowDelegate {
    private let activity: Activity
    private let vocabulary: VocabularyStore
    /// 初めて開くときに作る。
    private var window: NSWindow?

    init(activity: Activity, vocabulary: VocabularyStore) {
        self.activity = activity
        self.vocabulary = vocabulary
    }

    func show(_ pane: Activity.Pane? = nil) {
        if let pane { activity.pane = pane }
        vocabulary.reload()
        let window = self.window ?? {
            let window = Self.makeWindow(activity: activity, vocabulary: vocabulary)
            window.delegate = self
            window.setFrameAutosaveName("PokoMain")
            if !window.setFrameUsingName("PokoMain") { window.center() }
            self.window = window
            return window
        }()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { NSApp.hide(nil) }
    }

    /// 窓を作る（tools/render-window も同じものを描く）。
    static func makeWindow(activity: Activity, vocabulary: VocabularyStore) -> NSWindow {
        let hosting = NSHostingController(rootView: PokoView(activity: activity, vocabulary: vocabulary))
        hosting.sceneBridgingOptions = [.toolbars]  // SwiftUI の .toolbar を窓のツールバーに出す
        hosting.sizingOptions = [.minSize]  // 窓の大きさは中身に合わせず、自由に変えられるように
        let window = NSWindow(contentViewController: hosting)
        window.title = "Poko"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 560))
        return window
    }
}

struct PokoView: View {
    @ObservedObject var activity: Activity
    @ObservedObject var vocabulary: VocabularyStore

    var body: some View {
        Group {
            switch activity.pane {
            case .history: HistoryView(activity: activity)
            case .dictionary: DictionaryView(activity: activity, vocabulary: vocabulary)
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("表示", selection: $activity.pane) {
                    Text("履歴").tag(Activity.Pane.history)
                    Text("辞書").tag(Activity.Pane.dictionary)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

// MARK: 履歴

struct HistoryView: View {
    @ObservedObject var activity: Activity

    var body: some View {
        if activity.entries.isEmpty && activity.phase == .idle {
            ContentUnavailableView {
                Label("\(activity.keyLabel) を押しながら話す", systemImage: "waveform")
            } description: {
                Text("話した文がここに並びます。\nこの窓が前にあるときは、貼らずにここにだけ出します。")
            }
        } else {
            List {
                if activity.phase != .idle {
                    LiveRow(phase: activity.phase)
                        .listRowSeparator(.hidden)
                }
                ForEach(activity.entries) { entry in
                    EntryRow(entry: entry) { activity.remove(entry.id) }
                }
            }
            .listStyle(.inset)
            .animation(.snappy, value: activity.entries.map(\.id))
            .animation(.snappy, value: activity.phase)
        }
    }
}

/// 録っている間と、文字にしている間の1行。
struct LiveRow: View {
    let phase: Activity.Phase

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: phase == .listening)
                .foregroundStyle(.tint)
                .frame(width: 18)
            Text(title)
                .foregroundStyle(.secondary)
            if phase != .listening {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
        .font(.system(size: 14))
        .padding(.vertical, 8)
        .transition(.opacity)
    }

    private var title: String {
        switch phase {
        case .idle, .listening: "聴いています…"
        case .transcribing: "文字にしています…"
        case .polishing: "整えています…"
        }
    }
}

struct EntryRow: View {
    let entry: Activity.Entry
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.text)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(entry.date, style: .time)
                    if let raw = entry.raw {
                        Text("·")
                        Text("推敲済み").help("推敲する前: \(raw)")
                    }
                    if let note = entry.note {
                        Text("·")
                        Text(note).lineLimit(1).help(note)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                copy(entry.text)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("コピー")
            .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("コピー") { copy(entry.text) }
            if let raw = entry.raw {
                Button("推敲する前の文をコピー") { copy(raw) }
            }
            Divider()
            Button("削除", role: .destructive, action: remove)
        }
    }
}

// MARK: 辞書

struct DictionaryView: View {
    @ObservedObject var activity: Activity
    @ObservedObject var vocabulary: VocabularyStore
    @State private var selection = Set<Term.ID>()
    @FocusState private var focused: Term.ID?

    var body: some View {
        VStack(spacing: 0) {
            if vocabulary.terms.isEmpty {
                ContentUnavailableView {
                    Label("辞書は空です", systemImage: "character.book.closed")
                } description: {
                    Text("固有名詞や略語を、書き方と読みの組で足すと、\nその読みに聞こえた所がこの書き方になります。\n読みはひらがなで。いくつもあるときは「、」で区切ります。")
                } actions: {
                    Button("語を足す", action: add)
                }
                .frame(maxHeight: .infinity)
            } else {
                table
            }
            Divider()
            footer
            TryBar(activity: activity)
        }
    }

    private var table: some View {
        Table(vocabulary.terms, selection: $selection) {
            TableColumn("書き方") { term in
                TextField("書き方", text: binding(term.id).written)
                    .focused($focused, equals: term.id)
            }
            .width(min: 120, ideal: 180, max: 260)
            TableColumn("読み") { term in
                HStack(spacing: 6) {
                    TextField("よみ（ひらがな）", text: binding(term.id).readings)
                    if let hint = Vocabulary.hint(for: term) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                            .imageScale(.small)
                            .help(hint)
                    }
                }
            }
        }
        .alternatingRowBackgrounds(.disabled)
        .onDeleteCommand(perform: removeSelected)
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Button(action: add) {
                Image(systemName: "plus").frame(width: 22, height: 20)
            }
            .help("語を足す（⌘N）")
            .keyboardShortcut("n")
            Button(action: removeSelected) {
                Image(systemName: "minus").frame(width: 22, height: 20)
            }
            .help("選んだ語を消す（⌫）")
            .disabled(selection.isEmpty)
            Spacer()
            if let problem = vocabulary.problem {
                Text(problem).foregroundStyle(.red).lineLimit(1)
            } else {
                Text(vocabulary.terms.isEmpty ? "" : "\(vocabulary.terms.count) 語")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([Vocabulary.file])
            } label: {
                Image(systemName: "folder").frame(width: 22, height: 20)
            }
            .help("辞書のファイルを Finder で表示（1行に「書き方=読み」。手で直してもよい）")
            .padding(.leading, 6)
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private func binding(_ id: Term.ID) -> Binding<Term> {
        Binding {
            vocabulary.terms.first { $0.id == id } ?? Term(written: "", readings: "")
        } set: { term in
            if let index = vocabulary.terms.firstIndex(where: { $0.id == id }) { vocabulary.terms[index] = term }
        }
    }

    private func add() {
        let term = Term(written: "", readings: "")
        vocabulary.terms.append(term)
        selection = [term.id]
        DispatchQueue.main.async { focused = term.id }
    }

    private func removeSelected() {
        vocabulary.terms.removeAll { selection.contains($0.id) }
        selection = []
    }
}

/// 辞書の下の帯。語を足してすぐ話して試せるよう、いまの状態と最後の結果を出す。
struct TryBar: View {
    @ObservedObject var activity: Activity

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: activity.phase == .listening)
                .foregroundStyle(activity.phase == .idle ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .frame(width: 18)
            Group {
                switch activity.phase {
                case .listening: Text("聴いています…").foregroundStyle(.secondary)
                case .transcribing, .polishing: Text("文字にしています…").foregroundStyle(.secondary)
                case .idle:
                    if let last = activity.entries.first {
                        Text(last.text).textSelection(.enabled).lineLimit(2)
                    } else {
                        Text("\(activity.keyLabel) を押しながら話すと、ここで試せます").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .animation(.snappy, value: activity.phase)
    }
}

private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
