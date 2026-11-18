import AppKit

// 菜单栏按钮的渲染规则。只依赖 AppKit 与值类型，便于在没有界面的测试里断言。
enum MenuBarButton {
    static func configure(_ button: NSButton, icon: NSImage?, toolTip: String) {
        // 先清空文字再设置图片位置：AppKit 修改 title 时会改写 imagePosition。
        button.title = ""
        button.image = icon
        button.imagePosition = .imageOnly
        button.toolTip = toolTip
    }
}
