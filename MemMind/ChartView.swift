import SwiftUI

// MARK: - Layout constants

let COL_W:    CGFloat = 4
let BAR_W:    CGFloat = 3
let BLOCK_H:  CGFloat = 3
let ROW_H:    CGFloat = 4

// MARK: - Color palette

extension Color {
    static let chartBg         = Color(red: 0.051, green: 0.051, blue: 0.051)
    static let chartGrid       = Color(white: 0.10)
    static let chartDim        = Color(white: 0.42)
    static let chartWired      = Color(red: 0.039, green: 0.518, blue: 1.0)
    static let chartActive     = Color(red: 0.188, green: 0.820, blue: 0.345)
    static let chartInactive   = Color(red: 0.102, green: 0.322, blue: 0.192)
    static let chartCompressed = Color(red: 1.0,   green: 0.624, blue: 0.039)
    static let chartSwap       = Color(red: 1.0,   green: 0.271, blue: 0.227)
    static let chartSwapIn     = Color(red: 1.0,   green: 0.624, blue: 0.039)
    static let chartSwapOut    = Color(red: 1.0,   green: 0.271, blue: 0.227)
    static let chartWarn       = Color(red: 1.0,   green: 0.624, blue: 0.039)
    static let chartCrit       = Color(red: 1.0,   green: 0.271, blue: 0.227)
}

// MARK: - Tooltip line

struct TooltipLine {
    var dotColor: Color?   // nil = no dot (total/separator line)
    var label: String
    var value: String
    var gapBefore: Bool = false   // 上に区切りの隙間を入れる
}

// MARK: - Text with outline shadow

private func drawOutlined(
    _ ctx: GraphicsContext,
    text: Text,
    at point: CGPoint,
    anchor: UnitPoint
) {
    let shadow = text.foregroundColor(Color.black.opacity(0.85))
    for dx in [-1, 0, 1] as [CGFloat] {
        for dy in [-1, 0, 1] as [CGFloat] {
            guard dx != 0 || dy != 0 else { continue }
            ctx.draw(shadow, at: CGPoint(x: point.x + dx, y: point.y + dy), anchor: anchor)
        }
    }
    ctx.draw(text.foregroundColor(.white), at: point, anchor: anchor)
}

// MARK: - Bar segment

struct BarSegment {
    var fraction: Double
    var color: Color
}

// MARK: - Chart

struct ChartView: View {
    let title: String
    let bars: [[BarSegment]]
    let label: String
    let labelColor: Color
    /// Called with the hovered bar index (0 = oldest visible). Returns tooltip lines.
    var tooltipProvider: ((Int) -> [TooltipLine])? = nil

    @State private var hoverX: CGFloat? = nil

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height

            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.chartBg))

            // Grid lines
            for pct in [0.25, 0.50, 0.75] {
                let y = h * (1 - pct)
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: w, y: y))
                ctx.stroke(p, with: .color(.chartGrid), lineWidth: 1)
            }

            // Bars
            let n = bars.count
            for (i, segs) in bars.enumerated() {
                let x0 = w - CGFloat(n - i) * COL_W
                guard x0 + BAR_W >= 0 else { continue }
                var yBot = h
                for seg in segs {
                    let totalH = h * CGFloat(max(0, min(1, seg.fraction)))
                    guard totalH > 0 else { continue }
                    ctx.fill(Path(CGRect(x: x0, y: yBot - totalH, width: BAR_W, height: totalH)),
                             with: .color(seg.color))
                    yBot -= totalH
                }
            }

            // Pixel-grid overlay
            var cutY = h - BLOCK_H
            while cutY > -ROW_H {
                let lineY = cutY + BLOCK_H
                if lineY >= 0 && lineY <= h {
                    ctx.fill(Path(CGRect(x: 0, y: lineY, width: w, height: ROW_H - BLOCK_H)),
                             with: .color(.chartBg))
                }
                cutY -= ROW_H
            }

            // Hover cursor + tooltip
            if let hx = hoverX, let provider = tooltipProvider, n > 0 {
                // Cursor line
                var cur = Path()
                cur.move(to: CGPoint(x: hx, y: 0))
                cur.addLine(to: CGPoint(x: hx, y: h))
                ctx.stroke(cur, with: .color(.white.opacity(0.45)), lineWidth: 1)

                // Bar index under cursor (newest = rightmost)
                let barIdx = max(0, min(n - 1, n - Int(ceil((w - hx) / COL_W))))
                let lines = provider(barIdx)
                guard !lines.isEmpty else { return }

                drawTooltip(ctx, lines: lines, hx: hx, size: size)
            }

            // Title
            drawOutlined(ctx,
                         text: Text(title).font(.system(size: 13, weight: .bold)),
                         at: CGPoint(x: 5, y: 5), anchor: .topLeading)

            // Status label
            if !label.isEmpty {
                drawOutlined(ctx,
                             text: Text(label).font(.system(size: 13)),
                             at: CGPoint(x: 5, y: 21), anchor: .topLeading)
            }
        }
        .background(Color.chartBg)
        .onContinuousHover { phase in
            switch phase {
            case .active(let loc): hoverX = loc.x
            case .ended:           hoverX = nil
            }
        }
    }

    // MARK: - Tooltip drawing

    private func drawTooltip(
        _ ctx: GraphicsContext,
        lines: [TooltipLine],
        hx: CGFloat,
        size: CGSize
    ) {
        let w = size.width
        let h = size.height
        let lineH: CGFloat  = 17
        let gapH: CGFloat   = 8
        let dotSize: CGFloat = 8
        let padX: CGFloat   = 8
        let padY: CGFloat   = 6
        let boxW: CGFloat   = 160
        let totalGaps       = CGFloat(lines.filter { $0.gapBefore }.count) * gapH
        let boxH            = CGFloat(lines.count) * lineH + totalGaps + padY * 2

        // Place tooltip left or right of cursor, clamped inside chart
        let showRight = hx < w / 2
        var bx: CGFloat = showRight ? hx + 10 : hx - boxW - 10
        bx = max(2, min(w - boxW - 2, bx))
        let by: CGFloat = max(2, min(h - boxH - 2, 38))   // below title/label area

        // Background
        let bgRect = CGRect(x: bx, y: by, width: boxW, height: boxH)
        ctx.fill(Path(roundedRect: bgRect, cornerRadius: 6),
                 with: .color(Color.black.opacity(0.78)))

        // Lines
        var cursorY = by + padY
        for line in lines {
            if line.gapBefore { cursorY += gapH }
            let ly = cursorY

            if let dot = line.dotColor {
                ctx.fill(Path(roundedRect: CGRect(x: bx + padX, y: ly + (lineH - dotSize) / 2,
                                                   width: dotSize, height: dotSize),
                              cornerRadius: 2),
                         with: .color(dot))
            }

            let textX = bx + padX + dotSize + 5
            let valueX = bx + boxW - padX

            ctx.draw(
                Text(line.label).font(.system(size: 11)).foregroundColor(Color(white: 0.75)),
                at: CGPoint(x: textX, y: ly + lineH / 2), anchor: .leading
            )
            ctx.draw(
                Text(line.value).font(.system(size: 11, weight: .medium)).foregroundColor(.white),
                at: CGPoint(x: valueX, y: ly + lineH / 2), anchor: .trailing
            )
            cursorY += lineH
        }
    }
}
