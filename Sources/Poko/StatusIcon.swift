import AppKit

/// メニューバーのアイコン。5 本のバーが、そのまま声のメーターになる。
///
/// - 待っているとき: 静かな波形
/// - 押した瞬間: 点に縮む（聴いている）。話すと声の大きさに合わせて伸びる
/// - 認識しているとき: 点の上を波が左から右へ渡る
/// - 貼り終えたとき: ばねで波形に戻る
/// - 失敗したとき: 真ん中が「!」になる
/// - 準備ができていないとき（許可やモデルがない）: 波形が薄くなる
enum IconMode: Equatable {
    case unready, idle, recording, transcribing, error
}

/// バーの高さを、ばねで目標へ近づける。描画とは切り離してあり、時間を進めるだけで動きが決まる。
struct IconMotion {
    static let count = 5
    /// 待っているときの波形（pt）。
    static let rest: [CGFloat] = [4, 8, 12, 8, 4]
    static let dot: CGFloat = 2
    static let tallest: CGFloat = 16

    private(set) var heights: [CGFloat] = IconMotion.rest
    private var velocities = [CGFloat](repeating: 0, count: IconMotion.count)
    private(set) var mode: IconMode = .idle
    private var level: CGFloat = 0
    private var heard: CGFloat = 0
    private var popUntil: TimeInterval = 0

    /// `pop` なら、一瞬大きく跳ねてから戻る（貼り終えた合図）。
    mutating func set(_ mode: IconMode, at time: TimeInterval, pop: Bool = false) {
        popUntil = pop ? time + 0.12 : 0
        if mode != .recording { level = 0; heard = 0 }
        self.mode = mode
    }

    /// 声の大きさ（0〜1）。マイクから届くたび（およそ 0.1 秒ごと）に渡す。
    mutating func hear(_ input: Float) {
        heard = CGFloat(input)
    }

    /// 時間を `step` 秒進める。動き終わったら false を返す（描き直しを止めてよい）。
    mutating func advance(by step: TimeInterval, at time: TimeInterval) -> Bool {
        // 届いた大きさへ、時間を基準に近づける（上がるときは 0.04 秒、下がるときは 0.2 秒の時定数）。
        // 届く間隔に左右されないよう、ここで毎コマ近づける。
        let constant = heard > level ? 0.04 : 0.2
        level += (heard - level) * CGFloat(1 - exp(-step / constant))
        let goal = targets(at: time)
        // 録っている間は声に素直に、それ以外は少し弾むように。
        let stiffness: CGFloat = mode == .recording ? 900 : 420
        let damping: CGFloat = 2 * stiffness.squareRoot() * (mode == .recording ? 0.85 : 0.55)
        var moving = mode == .recording || mode == .transcribing || time < popUntil
        for i in 0..<Self.count {
            let force = stiffness * (goal[i] - heights[i]) - damping * velocities[i]
            velocities[i] += force * step
            heights[i] += velocities[i] * step
            if abs(goal[i] - heights[i]) > 0.02 || abs(velocities[i]) > 0.02 { moving = true }
        }
        return moving
    }

    func targets(at time: TimeInterval) -> [CGFloat] {
        switch mode {
        case .idle, .unready:
            let scale: CGFloat = time < popUntil ? 1.3 : 1
            return Self.rest.map { $0 * scale }
        case .recording:
            let weights: [CGFloat] = [0.42, 0.74, 1, 0.74, 0.42]
            let rates: [Double] = [2.3, 3.1, 1.9, 2.7, 3.5]  // それぞれ違う速さで揺らし、生きた声に見せる
            return (0..<Self.count).map { i in
                let sway = 0.6 + 0.4 * CGFloat(sin(time * rates[i] * 2 * .pi + Double(i) * 1.7))
                return Self.dot + (Self.tallest - Self.dot) * level * weights[i] * sway
            }
        case .transcribing:
            let period = 0.9
            return (0..<Self.count).map { i in
                let phase = (time - Double(i) * 0.09).truncatingRemainder(dividingBy: period) / period
                let bump = phase < 0.45 ? pow(sin(phase / 0.45 * .pi), 2) : 0
                return Self.dot + 5 * CGFloat(bump)
            }
        case .error:
            return [Self.dot, Self.dot, 12, Self.dot, Self.dot]
        }
    }
}

enum IconDrawing {
    static let size = NSSize(width: 18, height: 18)
    static let barWidth: CGFloat = 2
    static let pitch: CGFloat = 4  // バーの左端どうしの間隔。1x でも 2x でも画素に揃う

    /// テンプレート画像として描く（メニューバーの明暗に合わせて macOS が色を付ける）。
    static func image(heights: [CGFloat], mode: IconMode) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.withAlphaComponent(mode == .unready ? 0.35 : 1).setFill()
            let left = (size.width - pitch * CGFloat(heights.count - 1) - barWidth) / 2
            for (i, height) in heights.enumerated() {
                let x = left + CGFloat(i) * pitch
                if mode == .error && i == heights.count / 2 {
                    exclamation(x: x, height: height)
                } else {
                    capsule(x: x, centerY: size.height / 2, height: height)
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func capsule(x: CGFloat, centerY: CGFloat, height: CGFloat) {
        let height = max(height, barWidth)
        let rect = NSRect(x: x, y: centerY - height / 2, width: barWidth, height: height)
        NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    }

    /// 縦棒と点で「!」を描く。全体の高さは `height`。
    private static func exclamation(x: CGFloat, height: CGFloat) {
        let height = max(height, barWidth)
        let gap: CGFloat = 1.5
        let bottom = size.height / 2 - height / 2
        let stem = max(height - barWidth - gap, 0)
        capsule(x: x, centerY: bottom + barWidth / 2, height: barWidth)
        if stem > 0 {
            capsule(x: x, centerY: bottom + barWidth + gap + stem / 2, height: stem)
        }
    }
}
