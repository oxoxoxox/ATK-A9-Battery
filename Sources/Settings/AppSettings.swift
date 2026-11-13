import Combine
import Foundation

// 菜单栏按钮上鼠标图标旁边显示的内容。
enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case iconOnly
    case percentWithBolt
    case iconPercentWithBolt
    case iconPercent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconOnly: return "只显示鼠标图标"
        case .percentWithBolt: return "只显示电量数值和闪电"
        case .iconPercentWithBolt: return "鼠标图标、电量数值和闪电"
        case .iconPercent: return "鼠标图标和电量数值"
        }
    }

    var detail: String {
        switch self {
        case .iconOnly: return "占用空间最少，点击图标查看详情"
        case .percentWithBolt: return "充电时在数值后显示闪电"
        case .iconPercentWithBolt: return "默认。充电时在数值后显示闪电"
        case .iconPercent: return "数值后不显示闪电"
        }
    }

    var showsIcon: Bool {
        switch self {
        case .iconOnly, .iconPercentWithBolt, .iconPercent: return true
        case .percentWithBolt: return false
        }
    }

    var showsPercent: Bool {
        self != .iconOnly
    }

    var showsBolt: Bool {
        switch self {
        case .percentWithBolt, .iconPercentWithBolt: return true
        case .iconOnly, .iconPercent: return false
        }
    }
}

final class AppSettings: ObservableObject {
    static let menuBarDisplayKey = "menuBarDisplay"

    @Published var menuBarDisplay: MenuBarDisplay {
        didSet { defaults.set(menuBarDisplay.rawValue, forKey: Self.menuBarDisplayKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.menuBarDisplayKey).flatMap(MenuBarDisplay.init(rawValue:))
        menuBarDisplay = stored ?? .iconPercentWithBolt
    }
}
