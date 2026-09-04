import Foundation

@discardableResult
func expect(_ condition: Bool, _ message: String) -> Bool {
    if !condition {
        fputs("FAIL: \(message)\n", stderr)
        return false
    }
    return true
}

var failed = false

func check(_ condition: Bool, _ message: String) {
    if !expect(condition, message) { failed = true }
}

func runCompxCodecTests() {
    let batteryReport = CompxCodec.makeCommandReport(commandId: CompxCodec.cmdGetBattery)
    check(batteryReport.count == 17, "battery report length == 17")
    check(batteryReport[0] == 0x08, "report id byte")
    check(batteryReport[1] == 0x04, "command id")
    check(batteryReport[16] == 0x49, "checksum 0x49 for GetBatteryLevel")
    check(
        batteryReport[2..<16].allSatisfy { $0 == 0 },
        "payload[1..<15] zeros"
    )

    let mouseVersionReport = CompxCodec.makeCommandReport(commandId: CompxCodec.cmdGetMouseVersion)
    check(mouseVersionReport[1] == 0x12, "GetMouseVersion command")
    check(mouseVersionReport[16] == 0x3B, "checksum 0x3B")

    let webhid: [UInt8] = [
        0x04, 0x00, 0x00, 0x00, 0x02, 0x28, 0x00, 0x0F,
        0x4E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC2
    ]
    let webhidReading = CompxCodec.parseBattery(reportID: 0x08, bytes: webhid)
    check(webhidReading == BatteryReading(percent: 40, isCharging: false), "webhid battery 40%")

    let iokit: [UInt8] = [0x08] + webhid
    let iokitReading = CompxCodec.parseBattery(reportID: 0x08, bytes: iokit)
    check(iokitReading == BatteryReading(percent: 40, isCharging: false), "iokit prefixed battery 40%")

    let charging: [UInt8] = [
        0x04, 0x00, 0x00, 0x00, 0x02, 0x1E, 0x01, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ]
    check(
        CompxCodec.parseBattery(reportID: 0x08, bytes: charging) == BatteryReading(percent: 30, isCharging: true),
        "charging flag"
    )

    check(CompxCodec.parseBattery(reportID: 0x09, bytes: webhid) == nil, "wrong report id")
    check(CompxCodec.parseBattery(reportID: 0x08, bytes: [0x12, 0, 0, 0, 0, 1, 2]) == nil, "wrong command")

    let versionBytes: [UInt8] = [
        0x12, 0x00, 0x00, 0x00, 0x02, 0x01, 0x23, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ]
    let parsedVersion = CompxCodec.parseVersion(reportID: 0x08, bytes: versionBytes)
    check(parsedVersion?.commandId == 0x12, "version command id")
    check(parsedVersion?.version == "1.23", "version string 1.23")
}
