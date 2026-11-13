import AppKit

extension NSApplication {
    // LSUIElement 应用默认不在前台，弹出面板或关于窗口前需要手动激活，否则窗口可能不接收键盘和悬停。
    func bringToFront() {
        if #available(macOS 14.0, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}
