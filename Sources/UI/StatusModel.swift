import Combine
import Foundation
import SwiftUI

enum ConnectionState: Equatable {
    case searching
    case connected
    case notFound
    case failed(String)
}

// 界面只通过这些闭包触发动作，具体实现留在 AppDelegate。
struct AppActions {
    let willOpenPanel: () -> Void
    let refresh: () -> Void
    let requestInputMonitoring: () -> Void
    let toggleLaunchAtLogin: () -> Void
    let openLogFolder: () -> Void
    let showAbout: () -> Void
    let quit: () -> Void
}

enum StatusTone {
    case good
    case warning
    case critical
    case neutral

    var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        case .neutral: return .secondary
        }
    }
}

struct StatusHeadline {
    let text: String
    let symbol: String?
    let tone: StatusTone
}

final class StatusModel: ObservableObject {
    @Published var deviceName: String
    @Published private(set) var connection: ConnectionState = .searching
    @Published private(set) var reading: BatteryReading?
    @Published private(set) var updatedAt: Date?
    @Published var isRefreshing = false
    @Published var inputMonitoringGranted = false
    @Published var launchAtLogin = false
    @Published var nearcastConfigured = false

    init(deviceName: String) {
        self.deviceName = deviceName
    }

    // 有过读数，但当前接收器不可用：界面保留上一次电量并标为过期。
    var isStale: Bool {
        reading != nil && connection != .connected
    }

    // 未授权且读不到数据时，权限才是最可能的原因；已经连上就以实际读数为准。
    private var needsPermission: Bool {
        !inputMonitoringGranted && connection != .connected
    }

    func apply(_ update: BatteryUpdate, at date: Date = Date()) {
        isRefreshing = false
        switch update {
        case .reading(let snapshot):
            deviceName = snapshot.identity.displayName
            reading = snapshot.reading
            updatedAt = date
            connection = .connected
        case .notFound:
            connection = .notFound
        case .failed(let message):
            connection = .failed(message)
        }
    }

    var headline: StatusHeadline {
        if needsPermission {
            return StatusHeadline(text: "需要输入监控授权", symbol: "exclamationmark.triangle.fill", tone: .warning)
        }
        switch connection {
        case .searching:
            return StatusHeadline(text: "正在查找接收器", symbol: nil, tone: .neutral)
        case .notFound:
            return StatusHeadline(text: "未连接接收器", symbol: nil, tone: .neutral)
        case .failed:
            return StatusHeadline(text: "读取失败", symbol: "xmark.octagon.fill", tone: .critical)
        case .connected:
            guard let reading else {
                return StatusHeadline(text: "正在查找接收器", symbol: nil, tone: .neutral)
            }
            if reading.isCharging {
                return StatusHeadline(text: "充电中", symbol: "bolt.fill", tone: .good)
            }
            if reading.percent <= 10 {
                return StatusHeadline(text: "电量极低", symbol: nil, tone: .critical)
            }
            if reading.percent <= 20 {
                return StatusHeadline(text: "电量偏低", symbol: nil, tone: .warning)
            }
            return StatusHeadline(text: "电量正常", symbol: nil, tone: .good)
        }
    }

    var detail: String {
        if needsPermission {
            return "在“隐私与安全性 → 输入监控”中允许本应用"
        }
        switch connection {
        case .searching:
            return "首次读取中…"
        case .notFound:
            if isStale, let updatedAt { return "上次读数 \(time(updatedAt))" }
            return "请确认 2.4G 接收器已插好"
        case .failed(let message):
            return message
        case .connected:
            guard let updatedAt else { return "" }
            return "更新于 \(time(updatedAt))"
        }
    }

    var ringTone: StatusTone {
        guard let reading, !isStale else { return .neutral }
        if reading.isCharging { return .good }
        if reading.percent <= 10 { return .critical }
        if reading.percent <= 20 { return .warning }
        return .good
    }

    // 用于菜单栏提示和右键菜单标题，保持单行。
    var summary: String {
        guard let reading else {
            switch connection {
            case .searching: return "正在查找接收器…"
            case .notFound: return "\(deviceName) · 未连接"
            case .failed: return "\(deviceName) · 读取失败"
            case .connected: return deviceName
            }
        }
        let base = "\(deviceName) · \(reading.percent)%"
        if isStale { return base + "（未连接）" }
        return reading.isCharging ? base + " · 充电中" : base
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}
