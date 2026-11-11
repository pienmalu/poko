// アプリのアイコン（許可のダイアログや、システム設定の一覧に出る）を描く。
// メニューバーと同じ5本のバーを、墨色の角丸の上に置く。真ん中の1本は朱色。使い方: ./tools/render-app-icon.sh
import AppKit

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)  // 72 dpi のまま（iconutil は解像度も見る）
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(pixels) / 1024)  // 1024 の格子で描き、画素数に合わせて縮める
    scale.concat()

    // macOS のアイコンの格子: 1024 の中に 824 の本体、角の半径 185。
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor(srgbRed: 0.09, green: 0.09, blue: 0.1, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.2, green: 0.2, blue: 0.22, alpha: 1),
                        NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1)])!.draw(in: body, angle: -90)
    // 上の縁に、ごく薄い光。
    NSColor.white.withAlphaComponent(0.08).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
    rim.lineWidth = 3
    rim.stroke()

    // メニューバーと同じ比率のバー（18pt の中の 2pt 幅、4pt 間隔、高さ 4・8・12・8・4）。
    let unit: CGFloat = 26
    let heights: [CGFloat] = [4, 8, 12, 8, 4].map { $0 * unit }
    let width = 2 * unit, pitch = 4 * unit
    let left = 512 - (pitch * 4 + width) / 2
    for (i, height) in heights.enumerated() {
        let rect = NSRect(x: left + CGFloat(i) * pitch, y: 512 - height / 2, width: width, height: height)
        let bar = NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2)
        NSGraphicsContext.saveGraphicsState()
        bar.addClip()
        // 真ん中の1本だけ朱色にする（日本語の「声」のアプリとしての印）。
        let colors = i == 2
            ? [NSColor(srgbRed: 1, green: 0.42, blue: 0.27, alpha: 1), NSColor(srgbRed: 0.91, green: 0.22, blue: 0.11, alpha: 1)]
            : [NSColor(white: 1, alpha: 1), NSColor(white: 0.8, alpha: 1)]
        NSGradient(colors: colors)!.draw(in: rect, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.current = nil
    return rep
}

let set = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try! render(pixels: size * scale).representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent(name))
    }
}
print("wrote \(set.path)")
