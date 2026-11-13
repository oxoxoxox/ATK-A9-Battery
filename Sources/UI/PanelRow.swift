import SwiftUI

struct PanelIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.gradient))
    }
}

// 面板里的一行：action 为 nil 时只做展示，不响应点击也没有悬停高亮。
struct PanelRow<Trailing: View>: View {
    let icon: String
    let tint: Color
    let title: String
    var detail: String?
    var action: (() -> Void)?
    let trailing: Trailing

    @State private var hovering = false

    init(
        icon: String,
        tint: Color,
        title: String,
        detail: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.detail = detail
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        Button(action: action ?? {}) {
            HStack(spacing: 10) {
                PanelIcon(symbol: icon, tint: tint)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                trailing
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(action != nil)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
        )
        .onHover { hovering = action != nil && $0 }
    }
}

extension PanelRow where Trailing == EmptyView {
    init(icon: String, tint: Color, title: String, detail: String? = nil, action: (() -> Void)? = nil) {
        self.init(icon: icon, tint: tint, title: title, detail: detail, action: action) { EmptyView() }
    }
}

struct PanelChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
    }
}
