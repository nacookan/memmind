import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.configureWindows()
        }
    }

    private func configureWindows() {
        NSApplication.shared.windows.forEach {
            $0.styleMask = [.borderless, .resizable]
            $0.isMovableByWindowBackground = true
            $0.isOpaque = false
            $0.backgroundColor = .clear
            $0.hasShadow = true
        }
    }
}
