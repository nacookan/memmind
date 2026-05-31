#!/usr/bin/swift
// アイコン生成スクリプト — swift generate_icon.swift <output_dir>
import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// MARK: - Drawing

func makeIcon(px: Int) -> NSImage {
    let s = CGFloat(px)
    // CGBitmapContext で正確なピクセルサイズを指定（Retina倍率の影響なし）
    guard let ctx = CGContext(data: nil, width: px, height: px,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return NSImage() }

    // ── Background (dark rounded rect) ──────────────────────────
    let r = s * 0.18   // corner radius
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.setFillColor(CGColor(red: 0.051, green: 0.051, blue: 0.051, alpha: 1))
    ctx.addPath(bgPath)
    ctx.fillPath()

    // ── Bar chart ───────────────────────────────────────────────
    // Simulated memory stacks (inactive / active / compressed / wired)
    typealias Stack = (inactive: CGFloat, active: CGFloat, comp: CGFloat, wired: CGFloat)
    let stacks: [Stack] = [
        (0.52, 0.16, 0.13, 0.06), (0.49, 0.19, 0.14, 0.06),
        (0.46, 0.22, 0.15, 0.06), (0.48, 0.20, 0.14, 0.06),
        (0.50, 0.18, 0.13, 0.06), (0.47, 0.21, 0.15, 0.06),
        (0.45, 0.23, 0.15, 0.06), (0.48, 0.20, 0.14, 0.06),
        (0.51, 0.17, 0.13, 0.06), (0.47, 0.21, 0.15, 0.06),
        (0.44, 0.24, 0.16, 0.06), (0.46, 0.22, 0.15, 0.06),
    ]

    let padX  = s * 0.10
    let padY  = s * 0.10
    let availW = s - padX * 2
    let availH = s - padY * 2
    let n = CGFloat(stacks.count)
    let barW = availW / n * 0.72
    let step = availW / n

    // Block grid: 3px block, 1px gap (scaled)
    let unit = max(2.0, s / 128.0 * 4.0)
    let blockH = unit * 0.75

    for (i, st) in stacks.enumerated() {
        let x = padX + CGFloat(i) * step
        var yBase = padY

        let layers: [(CGFloat, CGColor)] = [
            (st.inactive, CGColor(red: 0.102, green: 0.322, blue: 0.192, alpha: 1)),
            (st.active,   CGColor(red: 0.188, green: 0.820, blue: 0.345, alpha: 1)),
            (st.comp,     CGColor(red: 1.0,   green: 0.624, blue: 0.039, alpha: 1)),
            (st.wired,    CGColor(red: 0.039, green: 0.518, blue: 1.0,   alpha: 1)),
        ]

        for (frac, color) in layers {
            let layerH = frac * availH
            // Draw as stacked pixel blocks
            var by = yBase
            while by < yBase + layerH {
                let bh = min(blockH, yBase + layerH - by)
                guard bh > 0 else { break }
                ctx.setFillColor(color)
                ctx.fill(CGRect(x: x, y: by, width: barW, height: bh))
                by += unit
            }
            yBase += layerH
        }
    }

    // ── Subtle vignette ─────────────────────────────────────────
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [CGColor(red: 0, green: 0, blue: 0, alpha: 0),
                 CGColor(red: 0, green: 0, blue: 0, alpha: 0.30)] as CFArray,
        locations: [0, 1]
    )!
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    ctx.drawRadialGradient(gradient,
                           startCenter: CGPoint(x: s/2, y: s/2), startRadius: s * 0.3,
                           endCenter:   CGPoint(x: s/2, y: s/2), endRadius:   s * 0.72,
                           options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    guard let cgImage = ctx.makeImage() else { return NSImage() }
    return NSImage(cgImage: cgImage, size: NSSize(width: s, height: s))
}

func savePNG(_ img: NSImage, path: String) throws {
    guard let tiff   = img.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png    = bitmap.representation(using: .png, properties: [:])
    else { throw NSError(domain: "icon", code: 1) }
    try png.write(to: URL(fileURLWithPath: path))
}

// MARK: - Generate

let sizes = [16, 32, 64, 128, 256, 512, 1024]
try FileManager.default.createDirectory(atPath: outDir,
                                        withIntermediateDirectories: true)
for px in sizes {
    let img  = makeIcon(px: px)
    let path = "\(outDir)/icon_\(px).png"
    try savePNG(img, path: path)
    print("✓ \(px)x\(px)  →  \(path)")
}
print("Done.")
