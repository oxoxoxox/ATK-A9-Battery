import Foundation

protocol BatteryProvider: AnyObject {
    var identity: DeviceIdentity { get }
    var queryInterval: TimeInterval { get }
    var timeout: TimeInterval { get }
    func readBattery() throws -> BatteryReading
}

struct BatterySnapshot {
    let identity: DeviceIdentity
    let reading: BatteryReading
}

enum DeviceCatalog {
    static func makeProviders() -> [BatteryProvider] {
        [ATKA9Provider()]
    }
}
