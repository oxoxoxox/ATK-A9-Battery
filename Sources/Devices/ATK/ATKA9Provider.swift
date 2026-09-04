import Foundation
import IOKit.hid

final class ATKA9Provider: BatteryProvider {
    let identity = DeviceIdentity(
        displayName: "ATK A9 Ultra Max三模",
        appName: "MouseBatteryBridge",
        accessoryIdentifier: "ATK-A9-2.4G",
        deviceType: "Mouse",
        receiverVendorID: 0x373B,
        accessoryProductID: 0x120F
    )
    let queryInterval: TimeInterval = 10
    let timeout: TimeInterval = 3

    private let match = HIDMatch(
        vendorID: 0x373B,
        productID: 0x11FE,
        usagePage: 0xFF05,
        usage: 0x00
    )
    private var didLogDeviceInfo = false

    func readBattery() throws -> BatteryReading {
        try HIDSession.withDevice(match, displayName: identity.displayName) { connection in
            // 首次读取时在同一会话里查鼠标/接收器版本，避免两次开关设备
            if !self.didLogDeviceInfo {
                self.logVersion(connection, commandId: CompxCodec.cmdGetMouseVersion, label: "GetMouseVersion")
                self.logVersion(connection, commandId: CompxCodec.cmdGetDongleVersion, label: "GetDongleVersion")
                self.didLogDeviceInfo = true
            }
            try connection.sendOutput(
                reportID: CompxCodec.outputReportID,
                bytes: CompxCodec.makeCommandReport(commandId: CompxCodec.cmdGetBattery)
            )
            return try connection.awaitInput(timeout: self.timeout) { reportID, bytes in
                MBLog.log("收到回包：\(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
                let reading = CompxCodec.parseBattery(reportID: reportID, bytes: bytes)
                if let reading {
                    MBLog.log("解析电量回包: percent=\(reading.percent), isCharging=\(reading.isCharging)")
                }
                return reading
            }
        }
    }

    private func logVersion(_ connection: HIDConnection, commandId: UInt8, label: String) {
        do {
            try connection.sendOutput(
                reportID: CompxCodec.outputReportID,
                bytes: CompxCodec.makeCommandReport(commandId: commandId)
            )
            let parsed = try connection.awaitInput(timeout: timeout) { reportID, bytes in
                CompxCodec.parseVersion(reportID: reportID, bytes: bytes).flatMap { pair in
                    pair.commandId == commandId ? pair : nil
                }
            }
            MBLog.log("\(label): \(parsed.version)")
        } catch {
            MBLog.log("\(label): 未收到有效响应")
        }
    }
}
