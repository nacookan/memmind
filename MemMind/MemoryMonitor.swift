import Foundation
import Darwin

// MARK: - Data types

struct MemorySnapshot {
    let timestamp: Date
    let pageSize: UInt64

    // vm_statistics64 fields (in bytes)
    let appMemory: UInt64   // (internal_page_count - purgeable_count) * pageSize — matches Activity Monitor "App Memory"
    let wired: UInt64
    let inactive: UInt64
    let compressed: UInt64
    let totalPhysical: UInt64

    // Swap (from sysctl vm.swapusage)
    let swapUsed: UInt64
    let swapTotal: UInt64
    let swapIn: UInt64    // cumulative pages since boot
    let swapOut: UInt64   // cumulative pages since boot

    // Derived — Activity Monitor の「使用済みメモリ」定義
    // 使用済み = アプリメモリ + 固定(wired) + 圧縮(compressed)
    var used: UInt64 { appMemory + wired + compressed }
    // 未使用 = 全体 − 使用。未使用のうち inactive 以外を「空き」とみなす。
    var unused: UInt64 { totalPhysical > used ? totalPhysical - used : 0 }
    var freeMem: UInt64 { unused > inactive ? unused - inactive : 0 }

    var usedFraction: Double   { Double(used)       / Double(max(totalPhysical, 1)) }
    var unusedFraction: Double { Double(unused)     / Double(max(totalPhysical, 1)) }
    var wiredFraction: Double  { Double(wired)      / Double(max(totalPhysical, 1)) }
    var appFraction: Double    { Double(appMemory)  / Double(max(totalPhysical, 1)) }
    var inactiveFraction: Double   { Double(inactive)   / Double(max(totalPhysical, 1)) }
    var compressedFraction: Double { Double(compressed) / Double(max(totalPhysical, 1)) }
    var freeFraction: Double       { Double(freeMem)    / Double(max(totalPhysical, 1)) }

    var pressure: Int {
        let swapBytes = Double(swapUsed)
        let usedFrac  = usedFraction
        if swapBytes > 1_000_000_000 || usedFrac > 0.90 { return 2 }
        if swapBytes > 100_000_000   || usedFrac > 0.75 { return 1 }
        return 0
    }

    static func current() -> MemorySnapshot? {
        let hostPort = mach_host_self()

        // Page size
        var pageSz: vm_size_t = 0
        host_page_size(hostPort, &pageSz)
        let ps = UInt64(pageSz)

        // VM statistics
        var vmInfo = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let ret = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard ret == KERN_SUCCESS else { return nil }

        // Physical RAM total
        var totalRam: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalRam, &size, nil, 0)

        // Swap
        var swapInfo = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swapInfo, &swapSize, nil, 0)

        // App Memory = internal pages - purgeable pages (matches Activity Monitor "App Memory")
        let internalPages  = UInt64(vmInfo.internal_page_count)
        let purgeablePages = UInt64(vmInfo.purgeable_count)
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0

        return MemorySnapshot(
            timestamp:     Date(),
            pageSize:      ps,
            appMemory:     appPages                             * ps,
            wired:         UInt64(vmInfo.wire_count)            * ps,
            inactive:      UInt64(vmInfo.inactive_count)        * ps,
            compressed:    UInt64(vmInfo.compressor_page_count) * ps,
            totalPhysical: totalRam,
            swapUsed:      swapInfo.xsu_used,
            swapTotal:     swapInfo.xsu_total,
            swapIn:        UInt64(vmInfo.swapins),
            swapOut:       UInt64(vmInfo.swapouts)
        )
    }
}

// MARK: - Monitor

final class MemoryMonitor: ObservableObject {
    @Published var snapshots: [MemorySnapshot] = []
    private(set) var interval: TimeInterval = MemoryMonitor.savedInterval

    private var timer: Timer?
    private let maxSnapshots = 600

    static var savedInterval: TimeInterval {
        let v = UserDefaults.standard.double(forKey: "updateInterval")
        return v > 0 ? v : 2.0
    }

    func start() {
        poll()
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// メニューから更新頻度が変更されたとき呼ばれる
    func setInterval(_ seconds: TimeInterval) {
        guard seconds > 0, seconds != interval else { return }
        interval = seconds
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard let snap = MemorySnapshot.current() else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.snapshots.append(snap)
            if self.snapshots.count > self.maxSnapshots {
                self.snapshots.removeFirst()
            }
        }
    }
}

// MARK: - Formatting helpers

func fmtBytes(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    if gb >= 1.0 { return gb >= 10 ? String(format: "%.0fGB", gb) : String(format: "%.1fGB", gb) }
    let mb = Double(bytes) / 1_048_576
    return String(format: "%.0fMB", mb)
}

func fmtRate(_ bytesPerSec: Double) -> String {
    if bytesPerSec < 1_024         { return String(format: "%.0fB/s",  bytesPerSec) }
    if bytesPerSec < 1_048_576     { return String(format: "%.0fKB/s", bytesPerSec / 1_024) }
    if bytesPerSec < 1_073_741_824 { return String(format: "%.1fMB/s", bytesPerSec / 1_048_576) }
    return String(format: "%.1fGB/s", bytesPerSec / 1_073_741_824)
}

/// Shorthand for NSLocalizedString
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
