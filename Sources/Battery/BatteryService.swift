import Foundation

final class BatteryService {
    private let providers: [BatteryProvider]
    private(set) var lastSnapshot: BatterySnapshot?

    init(providers: [BatteryProvider] = DeviceCatalog.makeProviders()) {
        self.providers = providers
    }

    var queryInterval: TimeInterval {
        providers.map(\.queryInterval).min() ?? 10
    }

    // 按 providers 顺序尝试 readBattery()：
    // - noReceiver 表示这只鼠标没插，继续下一个
    // - 其它错误只打日志并停止本轮（设备在但协议失败，不要误匹配下一只）
    // 全部 noReceiver 返回 nil，保留 lastSnapshot 但不对外返回新快照，
    // 调用方因此不会把电源项写成 0%。
    func update() -> BatterySnapshot? {
        var sawNonReceiverError = false
        for provider in providers {
            do {
                let reading = try provider.readBattery()
                let snapshot = BatterySnapshot(identity: provider.identity, reading: reading)
                lastSnapshot = snapshot
                return snapshot
            } catch BridgeError.noReceiver(let name) {
                MBLog.log("\(provider.identity.appName): 未找到接收器 \(name)")
            } catch {
                sawNonReceiverError = true
                MBLog.log("\(provider.identity.appName): \(error)")
                break
            }
        }
        if !sawNonReceiverError {
            MBLog.log("MouseBatteryBridge: 未匹配到已连接的鼠标接收器")
        }
        return nil
    }
}
