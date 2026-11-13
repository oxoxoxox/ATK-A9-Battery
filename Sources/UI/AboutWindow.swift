import AppKit
import SwiftUI

struct AboutView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text("MouseBatteryBridge")
                    .font(.system(size: 20, weight: .semibold))
                Text("ATK A9 Ultra Max三模 电量显示")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("版本 \(version) (\(build))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Text("读取 2.4G 接收器的鼠标电量，同步到 macOS 电池小组件与 AirBattery。")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(spacing: 12) {
                Link("项目主页", destination: URL(string: "https://github.com/oxoxoxox/ATK-A9-Battery")!)
                Text("·").foregroundStyle(.tertiary)
                Text("MIT License").foregroundStyle(.secondary)
            }
            .font(.callout)
            Text("致谢 LANMIN-X · OpenAI Codex")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("© 2026 LANMIN-X. Released under the MIT License.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(width: 340)
    }
}

final class AboutWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: AboutView())
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.title = "关于 MouseBatteryBridge"
            window.isReleasedWhenClosed = false
            window.setContentSize(hosting.view.fittingSize)
            window.center()
            self.window = window
        }
        NSApp.bringToFront()
        window?.makeKeyAndOrderFront(nil)
    }
}
