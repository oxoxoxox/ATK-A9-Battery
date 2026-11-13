import Foundation

enum BatteryUpdate {
    case reading(BatterySnapshot)
    case notFound
    case failed(String)
}

// 只能在同一个串行队列上调用：ATKA9Provider 的版本日志标记与 HIDSession 的设备列表标记都没有加锁。
final class BatteryService {
    private let providers: [BatteryProvider]

    init(providers: [BatteryProvider] = DeviceCatalog.makeProviders()) {
        self.providers = providers
    }

    var queryInterval: TimeInterval {
        providers.map(\.queryInterval).min() ?? 10
    }

    var fallbackDeviceName: String {
        providers.first?.identity.displayName ?? "鼠标"
    }

    // 按 providers 顺序尝试 readBattery()：
    // - noReceiver 表示这只鼠标没插，继续下一个
    // - 其它错误直接返回 failed（设备在但协议失败，不要误匹配下一只）
    // 全部 noReceiver 返回 notFound。调用方保留上一次读数，不会把电源项写成 0%。
    func update() -> BatteryUpdate {
        for provider in providers {
            do {
                let reading = try provider.readBattery()
                return .reading(BatterySnapshot(identity: provider.identity, reading: reading))
            } catch BridgeError.noReceiver(let name) {
                MBLog.log("\(provider.identity.appName): 未找到接收器 \(name)")
            } catch {
                MBLog.log("\(provider.identity.appName): \(error)")
                return .failed("\(error)")
            }
        }
        MBLog.log("MouseBatteryBridge: 未匹配到已连接的鼠标接收器")
        return .notFound
    }
}
