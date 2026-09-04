import Foundation
import IOKit

// Compx 私有协议编解码（来自 hub.atk.pro 逆向）：
// Output Report 0x08 携带 16 字节命令，Input Report 0x08 返回响应。
// 校验和公式：checkSum = 85 - (sum([reportID, ...payload[0..14]]) & 255)
// 纯协议代码，禁止 NSLog；日志放在 Provider / HIDSession。
enum CompxCodec {
    static let outputReportID: CFIndex = 0x08
    static let inputReportID: UInt32 = 0x08
    static let reportLength = 16  // payload 长度（不含 Report ID）
    static let cmdGetBattery: UInt8 = 0x04
    static let cmdGetMouseVersion: UInt8 = 0x12
    static let cmdGetDongleVersion: UInt8 = 0x1D
    static let calChecksumWithReportID = true

    static func calcChecksum(reportID: UInt8, data: [UInt8]) -> UInt8 {
        var total = data.prefix(15).reduce(0) { $0 + UInt32($1) }
        if calChecksumWithReportID {
            total += UInt32(reportID)
        }
        return UInt8((85 - (total & 255)) & 0xFF)
    }

    static func makeCommandReport(commandId: UInt8) -> [UInt8] {
        var payload = [UInt8](repeating: 0, count: reportLength)
        payload[0] = commandId
        payload[15] = calcChecksum(reportID: UInt8(outputReportID), data: payload)

        var report = [UInt8](repeating: 0, count: reportLength + 1)
        report[0] = UInt8(outputReportID)
        report[1...] = payload[0...]
        return report
    }

    static func stripReportIDIfNeeded(_ bytes: [UInt8]) -> [UInt8] {
        var payload = bytes
        if payload.first == UInt8(inputReportID) {
            payload.removeFirst()
        }
        return payload
    }

    // Compx 协议: GetBatteryLevel=0x04, 响应 commandId 回显 0x04
    // payload[5]=batteryLevel, payload[6]=batteryCharge
    static func parseBattery(reportID: UInt32, bytes: [UInt8]) -> BatteryReading? {
        guard reportID == inputReportID else { return nil }
        let payload = stripReportIDIfNeeded(bytes)
        guard payload.count > 6, payload[0] == cmdGetBattery else { return nil }
        let percent = Int(payload[5] & 0xFF)
        let isCharging = (payload[6] & 0xFF) != 0
        return BatteryReading(percent: percent, isCharging: isCharging)
    }

    // 解析版本响应（GetMouseVersion=0x12 / GetDongleVersion=0x1D）
    // 版本格式：payload[5]=主版本, payload[6]=次版本 → "X.YY" (hex)
    static func parseVersion(reportID: UInt32, bytes: [UInt8]) -> (commandId: UInt8, version: String)? {
        guard reportID == inputReportID else { return nil }
        let payload = stripReportIDIfNeeded(bytes)
        guard payload.count > 6 else { return nil }
        guard payload[0] == cmdGetMouseVersion || payload[0] == cmdGetDongleVersion else { return nil }
        return (payload[0], String(format: "%X.%02X", payload[5], payload[6]))
    }
}
