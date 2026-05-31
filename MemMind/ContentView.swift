import SwiftUI

struct ContentView: View {
    @EnvironmentObject var monitor: MemoryMonitor

    @State private var chartWidth: CGFloat = 400

    private var maxBars: Int { max(1, Int(chartWidth / COL_W)) }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                memPanel
                divider
                swapPanel
                divider
                ioPanel
            }
            .background(Color(red: 0.051, green: 0.051, blue: 0.051))
            .onChange(of: geo.size.width) { _, w in chartWidth = w }
            .onAppear { chartWidth = geo.size.width }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(minWidth: 260, minHeight: 180)
    }

    // MARK: - Panels

    private var memPanel: some View {
        let snaps = trimmed(monitor.snapshots)
        let bars  = snaps.map { memBar($0) }
        let label = snaps.last.map { memLabel($0) } ?? ""
        let color = snaps.last.map { pressureColor($0.pressure) } ?? .chartDim
        return ChartView(
            title: L("chart.memory"), bars: bars, label: label, labelColor: color,
            tooltipProvider: { idx in
                guard idx < snaps.count else { return [] }
                let s = snaps[idx]
                let usedPct   = Int(s.usedFraction * 100)
                let unusedPct = Int(s.unusedFraction * 100)
                return [
                    // 使用系
                    TooltipLine(dotColor: .chartActive,     label: L("tip.app"),        value: fmtBytes(s.appMemory)),
                    TooltipLine(dotColor: .chartWired,      label: L("tip.wired"),      value: fmtBytes(s.wired)),
                    TooltipLine(dotColor: .chartCompressed, label: L("tip.compressed"), value: fmtBytes(s.compressed)),
                    TooltipLine(dotColor: nil,              label: L("tip.used"),       value: "\(fmtBytes(s.used)) (\(usedPct)%)"),
                    // 未使用系
                    TooltipLine(dotColor: nil,              label: L("tip.free"),       value: fmtBytes(s.freeMem),  gapBefore: true),
                    TooltipLine(dotColor: .chartInactive,   label: L("tip.inactive"),   value: fmtBytes(s.inactive)),
                    TooltipLine(dotColor: nil,              label: L("tip.unused"),     value: "\(fmtBytes(s.unused)) (\(unusedPct)%)"),
                ]
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var swapPanel: some View {
        let snaps   = trimmed(monitor.snapshots)
        let maxSwap = snaps.map { max(Double($0.swapUsed) * 2, 8 * 1_073_741_824.0) }.max() ?? 8_589_934_592
        let bars    = snaps.map { swapBar($0, scale: maxSwap) }
        let label   = snaps.last.map { fmtBytes($0.swapUsed) } ?? ""
        let color: Color = (snaps.last?.swapUsed ?? 0) > 0 ? .chartSwap : .chartDim
        return ChartView(
            title: L("chart.swap"), bars: bars, label: label, labelColor: color,
            tooltipProvider: { idx in
                guard idx < snaps.count else { return [] }
                let s = snaps[idx]
                return [
                    TooltipLine(dotColor: .chartSwap, label: L("tip.swap"), value: fmtBytes(s.swapUsed)),
                ]
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ioPanel: some View {
        let (bars, rates, label, color) = ioBars()
        return ChartView(
            title: L("chart.swap_io"), bars: bars, label: label, labelColor: color,
            tooltipProvider: { idx in
                guard idx < rates.count else { return [] }
                let r = rates[idx]
                return [
                    TooltipLine(dotColor: .chartSwapIn,  label: L("io.in"),  value: fmtRate(r.sin)),
                    TooltipLine(dotColor: .chartSwapOut, label: L("io.out"), value: fmtRate(r.sout)),
                ]
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var divider: some View {
        Color(white: 0.50).frame(height: 4)
    }

    // MARK: - Bar builders

    private func trimmed(_ snaps: [MemorySnapshot]) -> [MemorySnapshot] {
        snaps.count > maxBars ? Array(snaps.suffix(maxBars)) : snaps
    }

    private func memBar(_ s: MemorySnapshot) -> [BarSegment] {
        // 下→上: 使用系（アプリ・圧縮・固定）→ 非活性。残りの余白が「空き」。
        var segs: [BarSegment] = [
            BarSegment(fraction: s.appFraction,        color: .chartActive),
            BarSegment(fraction: s.compressedFraction, color: .chartCompressed),
            BarSegment(fraction: s.wiredFraction,      color: .chartWired),
            BarSegment(fraction: s.inactiveFraction,   color: .chartInactive),
        ]
        let total = segs.reduce(0.0) { $0 + $1.fraction }
        if total > 1.0 {
            let k = 1.0 / total
            segs = segs.map { BarSegment(fraction: $0.fraction * k, color: $0.color) }
        }
        return segs
    }

    private func memLabel(_ s: MemorySnapshot) -> String {
        let usedGB  = Double(s.used)          / 1_073_741_824
        let totalGB = Double(s.totalPhysical) / 1_073_741_824
        let pct     = s.usedFraction * 100
        return String(format: L("mem.used_fmt"),
                      usedGB, totalGB, pct,
                      fmtBytes(s.wired), fmtBytes(s.compressed))
    }

    private func swapBar(_ s: MemorySnapshot, scale: Double) -> [BarSegment] {
        let f = scale > 0 ? min(1.0, Double(s.swapUsed) / scale) : 0.0
        return [BarSegment(fraction: f, color: .chartSwap)]
    }

    private func ioBars() -> ([[BarSegment]], [(sin: Double, sout: Double)], String, Color) {
        let sliced = trimmed(monitor.snapshots)
        guard sliced.count > 1 else {
            let empty = Array(repeating: (sin: 0.0, sout: 0.0), count: sliced.count)
            return (Array(repeating: [], count: sliced.count), empty, "In 0B/s\nOut 0B/s", .chartDim)
        }

        var rates: [(sin: Double, sout: Double)] = [(0, 0)]
        for i in 1..<sliced.count {
            let cur = sliced[i], prev = sliced[i - 1]
            let dt  = cur.timestamp.timeIntervalSince(prev.timestamp)
            guard dt > 0 else { rates.append((0, 0)); continue }
            let ps    = Double(cur.pageSize)
            let sinR  = Double(cur.swapIn  > prev.swapIn  ? cur.swapIn  - prev.swapIn  : 0) * ps / dt
            let soutR = Double(cur.swapOut > prev.swapOut ? cur.swapOut - prev.swapOut : 0) * ps / dt
            rates.append((sinR, soutR))
        }

        let ceiling = max(rates.map { $0.sin + $0.sout }.max() ?? 0, 1_048_576.0)

        var bars: [[BarSegment]] = rates.map { r in
            guard r.sin + r.sout > 0 else { return [] }
            return [
                BarSegment(fraction: min(1.0, r.sout / ceiling), color: .chartSwapOut),
                BarSegment(fraction: min(1.0, r.sin  / ceiling), color: .chartSwapIn),
            ]
        }
        while bars.count < sliced.count { bars.insert([], at: 0) }

        let last  = rates.last ?? (0, 0)
        let label = "\(L("io.in")) \(fmtRate(last.sin))\n\(L("io.out")) \(fmtRate(last.sout))"
        let color: Color = last.sout > 1_048_576 ? .chartCrit
                         : last.sin  > 1_048_576 ? .chartWarn
                         : .chartDim
        return (bars, rates, label, color)
    }

    private func pressureColor(_ p: Int) -> Color {
        switch p {
        case 2: return .chartCrit
        case 1: return .chartWarn
        default: return .chartDim
        }
    }
}
