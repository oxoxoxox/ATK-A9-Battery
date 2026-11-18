import AppKit

func runMenuBarButtonTests() {
    let icon = NSImage(size: NSSize(width: 22, height: 22))
    let button = NSButton(title: "85%", target: nil, action: nil)

    MenuBarButton.configure(button, icon: icon, toolTip: "提示")

    check(button.title.isEmpty, "menu bar button has no text")
    check(button.image === icon, "menu bar button shows the battery ring icon")
    check(button.imagePosition == .imageOnly, "menu bar button keeps imageOnly after the title is cleared")
    check(button.toolTip == "提示", "tooltip is applied")
}
