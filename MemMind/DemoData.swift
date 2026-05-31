import Foundation

// MARK: - Demo mode
// 起動時に --demo を渡すと実データの代わりにこのダミーデータを使う。
// スクリーンショット撮影用。更新なし、固定表示。

extension MemoryMonitor {

    func startDemo() {
        snapshots = Self.makeDemoSnapshots()
        // タイマーは起動しない（静止画）
    }

    // MARK: - Snapshot generation

    static func makeDemoSnapshots() -> [MemorySnapshot] {
        let total:    UInt64 = 32 * gb   // 32 GB
        let wired:    UInt64 = 7 * gb    // 固定（カーネル・GPU）: 一定
        let inactive: UInt64 = 2 * gb    // 非活性キャッシュ: ほぼ一定

        let count = 200
        let now   = Date()
        var snaps: [MemorySnapshot] = []

        // スワップ累積カウンタ（delta が I/O レートになる）
        var swapIn:  UInt64 = 10_000
        var swapOut: UInt64 =  4_000

        // I/O パターン定義: (index, swapInDelta, swapOutDelta)
        // 大スパイク × 2、中スパイク × 4、小スパイク多数、常時トリクル
        let ioPattern: [Int: (UInt64, UInt64)] = [
            // 大スパイク
            55:  (1_600, 600),
            140: (1_400, 500),
            // 中スパイク
            20:  (500, 150),
            80:  (450, 130),
            110: (480, 160),
            175: (420, 120),
            // 小スパイク（あちこちに）
            8:   (120,  30),
            15:  ( 90,  20),
            33:  (110,  25),
            45:  ( 80,  15),
            65:  (130,  40),
            75:  ( 70,  10),
            95:  (100,  20),
            105: ( 85,  15),
            120: (140,  35),
            130: ( 75,  10),
            150: ( 95,  25),
            160: (110,  30),
            185: ( 80,  20),
            193: (100,  25),
        ]

        for i in 0..<count {
            let t = Double(i) / Double(count - 1)   // 0.0 → 1.0

            // アプリメモリ: 9 GB → 15 GB に緩やかに増加 + 小さな揺らぎ
            let appGB   = 9.0 + t * 6.0 + sin(Double(i) * 0.4) * 0.25
            let compGB  = 2.0 + t * 0.5 + sin(Double(i) * 0.6) * 0.1
            let appMem  = UInt64(appGB * Double(gb))
            let comp    = UInt64(compGB * Double(gb))

            // スワップ: 0.4 GB → 0.6 GB に微増
            let swapGB   = 0.40 + t * 0.20 + sin(Double(i) * 0.2) * 0.01
            let swapUsed = UInt64(swapGB * Double(gb))

            // I/O: 常時トリクル + パターンスパイク
            let trickle: UInt64 = UInt64.random(in: 8...25)
            let (inDelta, outDelta) = ioPattern[i] ?? (trickle, trickle / 4)
            swapIn  += inDelta
            swapOut += outDelta

            snaps.append(MemorySnapshot(
                timestamp:     now.addingTimeInterval(Double(i - count) * 2.0),
                pageSize:      16_384,
                appMemory:     appMem,
                wired:         wired,
                inactive:      inactive,
                compressed:    comp,
                totalPhysical: total,
                swapUsed:      swapUsed,
                swapTotal:     10 * gb,
                swapIn:        swapIn,
                swapOut:       swapOut
            ))
        }
        return snaps
    }

    private static let gb: UInt64 = 1_073_741_824
}
