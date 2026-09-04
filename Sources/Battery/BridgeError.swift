import Foundation
import IOKit

enum BridgeError: Error, CustomStringConvertible {
    case noReceiver(String)
    case open(IOReturn)
    case send(IOReturn)
    case noResponse(TimeInterval)
    case powerSource(IOReturn)

    var description: String {
        switch self {
        case .noReceiver(let name):
            return "未找到 \(name) 接收器"
        case .open(let result):
            return "打开 HID 接收器失败：0x\(String(UInt32(bitPattern: result), radix: 16, uppercase: true))"
        case .send(let result):
            return "发送查询失败：0x\(String(UInt32(bitPattern: result), radix: 16, uppercase: true))"
        case .noResponse(let timeout):
            return "\(Int(timeout)) 秒内未收到有效电量回包"
        case .powerSource(let result):
            return "发布系统电源项失败：0x\(String(UInt32(bitPattern: result), radix: 16, uppercase: true))"
        }
    }
}
