import SwiftUI

@main
struct MemMindApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var monitor = MemoryMonitor()
    @AppStorage("updateInterval") private var interval: Double = 2.0

    private let isDemo = CommandLine.arguments.contains("--demo")

    var body: some Scene {
        Window("MemMind", id: "main") {
            ContentView()
                .environmentObject(monitor)
                .onAppear {
                    if isDemo {
                        monitor.startDemo()
                    } else {
                        monitor.start()
                        monitor.setInterval(interval)
                    }
                }
                .onDisappear { monitor.stop() }
                .onChange(of: interval) { _, newValue in
                    monitor.setInterval(newValue)
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 400, height: 520)
        .commands {
            // 不要な標準メニュー項目を削除
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .pasteboard) {}
            CommandGroup(replacing: .help) {}

            // 独自の「更新頻度」メニュー。Picker(.inline) なので
            // 現在値に自動でチェックマークが付く。
            CommandMenu(L("menu.interval")) {
                Picker("", selection: $interval) {
                    Text(secLabel(0.1)).tag(0.1)
                    Text(secLabel(1)).tag(1.0)
                    Text(secLabel(2)).tag(2.0)
                    Text(secLabel(5)).tag(5.0)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
    }

    private func secLabel(_ v: Double) -> String {
        let n = v == 0.1 ? "0.1" : String(Int(v))
        return n + L("menu.interval.sec")
    }
}
