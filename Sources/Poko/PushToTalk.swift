import Foundation

/// キーの押し離しから「録り始める・捨てる・認識する」を決める。副作用はないのでテストできる。
///
/// - 押したら録り始める
/// - 押している間に別のキーが来たら、それはショートカット（右⌘+C など）なので捨てる
/// - すぐ離したら（`minimumHold` 未満）、押し間違いとみなして捨てる
/// - 離すか、録れる長さの上限に達したら認識する
/// - 認識している間の押下は無視する
struct PushToTalk {
    enum State: Equatable {
        case idle
        case recording(since: TimeInterval)
        case transcribing
    }

    enum Event: Equatable {
        case keyDown(at: TimeInterval)
        case keyUp(at: TimeInterval)
        case otherInput
        case timeLimit
        case finished
    }

    enum Action: Equatable {
        case start
        case cancel
        case finish
    }

    static let minimumHold: TimeInterval = 0.3

    private(set) var state: State = .idle

    mutating func handle(_ event: Event) -> Action? {
        switch (state, event) {
        case (.idle, .keyDown(let time)):
            state = .recording(since: time)
            return .start
        case (.recording, .otherInput):
            state = .idle
            return .cancel
        case (.recording(let since), .keyUp(let time)):
            if time - since < Self.minimumHold {
                state = .idle
                return .cancel
            }
            state = .transcribing
            return .finish
        case (.recording, .timeLimit):
            state = .transcribing
            return .finish
        case (.transcribing, .finished):
            state = .idle
            return nil
        default:
            return nil
        }
    }

    /// 録り始められなかったときなどに、待っている状態へ戻す。
    mutating func reset() {
        state = .idle
    }
}
