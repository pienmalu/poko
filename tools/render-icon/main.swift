// アイコンの動きをコマ送りで1枚の PNG に描く（見た目の確認用）。使い方: ./tools/render-icon.sh 出力.png
import AppKit

struct Row { let title: String; let frames: [(heights: [CGFloat], mode: IconMode)] }

func simulate(_ title: String, count: Int = 12, every: Double = 1.0 / 15, setup: (inout IconMotion) -> Void,
              level: (Double) -> Float = { _ in 0 }) -> Row {
    var motion = IconMotion()
    var time = 0.0
    setup(&motion)
    var frames: [(heights: [CGFloat], mode: IconMode)] = []
    var next = 0.0
    while frames.count < count {
        if Int(time * 60) % 6 == 0 { motion.hear(level(time)) }  // 本物のマイクと同じく、およそ 0.1 秒ごとに届く
        _ = motion.advance(by: 1.0 / 60, at: time)
        time += 1.0 / 60
        if time >= next { frames.append((motion.heights, motion.mode)); next += every }
    }
    return Row(title: title, frames: frames)
}

let speech: (Double) -> Float = { t in  // 話し声らしく、音節ごとに上下する大きさ
    Float(max(0, min(1, 0.55 + 0.35 * sin(t * 9) * sin(t * 2.3 + 1) + 0.1 * sin(t * 23))))
}
let rows = [
    simulate("idle", count: 1, setup: { $0.set(.idle, at: 0) }),
    simulate("unready", count: 1, setup: { $0.set(.unready, at: 0) }),
    simulate("press: rest → listening (silent)", setup: { $0.set(.recording, at: 0) }),
    simulate("recording: speaking", setup: { $0.set(.recording, at: 0) }, level: speech),
    simulate("transcribing", setup: { $0.set(.transcribing, at: 0) }),
    simulate("done: pop → rest", every: 1.0 / 30, setup: { m in
        m.set(.transcribing, at: 0); for i in 0..<20 { _ = m.advance(by: 1.0 / 60, at: Double(i) / 60) }
        m.set(.idle, at: 0, pop: true)
    }),
    simulate("error", setup: { $0.set(.error, at: 0) }),
]

let scale: CGFloat = 4, cell = IconDrawing.size.width * scale, pad: CGFloat = 10, label: CGFloat = 230
let columns = rows.map(\.frames.count).max()!
let bars: [(name: String, background: NSColor, ink: NSColor, scale: CGFloat)] = [
    ("light 2x", NSColor(white: 0.93, alpha: 1), NSColor(white: 0.1, alpha: 1), 2),
    ("dark 2x", NSColor(white: 0.16, alpha: 1), NSColor(white: 0.96, alpha: 1), 2),
    ("light 1x", NSColor(white: 0.93, alpha: 1), NSColor(white: 0.1, alpha: 1), 1),
]
let width = label + CGFloat(columns) * (cell + pad) + pad
let blockHeight = CGFloat(rows.count) * (cell + pad) + 30
let height = blockHeight * CGFloat(bars.count)
let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()

for (b, bar) in bars.enumerated() {
    let top = height - CGFloat(b) * blockHeight
    NSString(string: bar.name).draw(at: NSPoint(x: pad, y: top - 22), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
    for (r, row) in rows.enumerated() {
        let y = top - 30 - CGFloat(r + 1) * (cell + pad)
        NSString(string: row.title).draw(at: NSPoint(x: pad, y: y + cell / 2 - 8), withAttributes: [.font: NSFont.systemFont(ofSize: 13)])
        for (c, frame) in row.frames.enumerated() {
            let rect = NSRect(x: label + CGFloat(c) * (cell + pad), y: y, width: cell, height: cell)
            bar.background.setFill(); rect.fill()
            // テンプレート画像を、メニューバーと同じように色を付けて、1x/2x の画素に落としてから拡大する。
            let pixels = Int(IconDrawing.size.width * bar.scale)
            let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            small.size = IconDrawing.size
            let saved = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
            let image = IconDrawing.image(heights: frame.heights, mode: frame.mode)
            image.draw(in: NSRect(origin: .zero, size: IconDrawing.size))
            bar.ink.set(); NSRect(origin: .zero, size: IconDrawing.size).fill(using: .sourceIn)
            NSGraphicsContext.current = saved
            NSGraphicsContext.current?.imageInterpolation = .none
            small.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        }
    }
}
NSGraphicsContext.current = nil
try! canvas.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
