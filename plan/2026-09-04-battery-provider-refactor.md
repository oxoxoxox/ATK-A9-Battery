# BatteryProvider 重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把单文件 `MouseBatteryBridge.swift` 拆成「采集 / 传输 / 发布 / App」边界，使新增一只同类 HID 鼠标只需加 Provider，不必改菜单栏、电源项和 Nearcast。

**Architecture:** App 只依赖 `BatteryProvider` 和 `BatteryReading`。HID 开设备、发 Output Report、等 Input Report 放进 `HIDSession`。ATK A9 的 Compx 组包/校验/解析放进 `CompxCodec` + `ATKA9Provider`。系统电源项和 AirBattery Nearcast 只消费 `DeviceIdentity` + `BatteryReading`。同一时间只服务第一只匹配成功的鼠标。

**Tech Stack:** Swift 5 / macOS 13+ / arm64 / AppKit / IOKit.hid / MultipeerConnectivity / ServiceManagement / `swiftc` + `build.sh`（不引入 Xcode 工程或 SPM）。

## Global Constraints

- 目标：`arm64-apple-macos13.0`；构建入口仍是仓库根目录 `build.sh`。
- 用户可见行为不变：菜单栏、输入监控、开机启动、10 秒轮询、失败保留上次电量、Nearcast `nearcastGroupID`、退出时发离线。
- 不引入插件、动态加载、多设备同时发布。
- 不把 Feature Report / BLE / Chrome CDP 做成抽象；那些以后各自写新的 `BatteryProvider`。
- 纯协议代码（`CompxCodec`）禁止 `NSLog`；日志放在 Provider / HIDSession。
- 协议与类型名以本文件为准；实现时不要再发明第二套同义名称。
- 每完成一个 Task 再提交一次；未完成的 Task 不要混进同一 commit。

---

## File Map

拆完后删除根目录 `MouseBatteryBridge.swift`。App 由 `Sources/**/*.swift` 编译；测试只编译 codec 相关文件。

```
Sources/
  Battery/
    BatteryReading.swift      # 电量值对象
    DeviceIdentity.swift      # 展示名 / 电源项 / Nearcast 身份
    BridgeError.swift         # 统一错误
    BatteryProvider.swift     # 采集协议 + DeviceCatalog
    BatteryService.swift      # 轮询、选设备、保留上次读数
  HID/
    HIDMatch.swift            # VID/PID/Usage 匹配
    HIDSession.swift          # IOKit 打开、发送、等待 Input Report
  Devices/
    Compx/
      CompxCodec.swift        # Compx 校验和、组包、解析
    ATK/
      ATKA9Provider.swift     # ATK A9 Ultra Max 采集实现
  Publishers/
    PowerSource.swift         # 非公开 IOPS 电源项
    NearcastSender.swift      # AirBattery Nearcast
  App/
    AppDelegate.swift         # 菜单栏、权限、定时器、接线
    main.swift                # NSApplication 入口
Tests/
  CompxCodecTests.swift       # 无硬件的 codec 断言
build.sh                      # 编译 Sources 下全部 Swift
test.sh                       # 编译并运行 CompxCodecTests
```

数据流：

```
Timer → BatteryService.update()
          → DeviceCatalog.providers 逐个 try readBattery()
          → ATKA9Provider
               → HIDSession.withDevice(HIDMatch)
               → CompxCodec.makeCommandReport / parseBattery
          → BatterySnapshot(identity, reading)
     → PowerSource.publish
     → NearcastSender.update
```

加下一只鼠标：新建 `Sources/Devices/<Vendor>/<Name>Provider.swift`（需要私有协议时再加 `*Codec.swift`），在 `DeviceCatalog.makeProviders()` 里追加一行。

---

### Task 1: 核心值对象与 Provider 协议

**Files:**
- Create: `Sources/Battery/BatteryReading.swift`
- Create: `Sources/Battery/DeviceIdentity.swift`
- Create: `Sources/Battery/BridgeError.swift`
- Create: `Sources/Battery/BatteryProvider.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `struct BatteryReading: Equatable` — `percent: Int`, `isCharging: Bool`
  - `struct DeviceIdentity: Equatable` — 见下方字段
  - `enum BridgeError: Error, CustomStringConvertible`
  - `protocol BatteryProvider`
  - `enum DeviceCatalog` — `static func makeProviders() -> [BatteryProvider]`
  - `struct BatterySnapshot`

- [ ] **Step 1: 写入四个文件**

`Sources/Battery/BatteryReading.swift`:

```swift
import Foundation

struct BatteryReading: Equatable {
    let percent: Int
    let isCharging: Bool
}
```

`Sources/Battery/DeviceIdentity.swift`:

```swift
import Foundation

struct DeviceIdentity: Equatable {
    let displayName: String
    let appName: String
    let accessoryIdentifier: String
    let deviceType: String
    let receiverVendorID: Int
    let accessoryProductID: Int
}
```

`Sources/Battery/BridgeError.swift`:

```swift
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
```

`Sources/Battery/BatteryProvider.swift`:

```swift
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
        []
    }
}
```

本 Task 故意让 `makeProviders()` 返回空数组；Task 4 再填入 `ATKA9Provider()`。`BatteryProvider` 必须是 `AnyObject`，因为 ATK 实现要记住是否已打过版本日志。

- [ ] **Step 2: 确认文件存在且无旧类型名**

Run:

```bash
rg -n "enum DeviceAdapter|struct BatteryReading|protocol BatteryProvider" Sources MouseBatteryBridge.swift
```

Expected: `Sources/Battery/` 下能搜到新类型；`DeviceAdapter` 仍只存在于旧的 `MouseBatteryBridge.swift`（尚未删除）。

- [ ] **Step 3: Commit**

```bash
git add Sources/Battery/BatteryReading.swift Sources/Battery/DeviceIdentity.swift Sources/Battery/BridgeError.swift Sources/Battery/BatteryProvider.swift
git commit -m "refactor: extract battery value types and BatteryProvider protocol"
```

---

### Task 2: CompxCodec 与无硬件测试

**Files:**
- Create: `Sources/Devices/Compx/CompxCodec.swift`
- Create: `Tests/CompxCodecTests.swift`
- Create: `test.sh`

**Interfaces:**
- Consumes: `BatteryReading`
- Produces:
  - `enum CompxCodec`
  - `CompxCodec.outputReportID: CFIndex = 0x08`
  - `CompxCodec.inputReportID: UInt32 = 0x08`
  - `CompxCodec.reportLength = 16`
  - `CompxCodec.cmdGetBattery: UInt8 = 0x04`
  - `CompxCodec.cmdGetMouseVersion: UInt8 = 0x12`
  - `CompxCodec.cmdGetDongleVersion: UInt8 = 0x1D`
  - `CompxCodec.calcChecksum(reportID:data:) -> UInt8`
  - `CompxCodec.makeCommandReport(commandId:) -> [UInt8]`
  - `CompxCodec.parseBattery(reportID:bytes:) -> BatteryReading?`
  - `CompxCodec.parseVersion(reportID:bytes:) -> (commandId: UInt8, version: String)?`

- [ ] **Step 1: 先写测试（此时编译应失败）**

`Tests/CompxCodecTests.swift`:

```swift
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

if failed {
    fputs("CompxCodec tests failed\n", stderr)
    exit(1)
}
print("CompxCodec tests passed")
```

`test.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h}
out="$project_dir/dist/CompxCodecTests"
mkdir -p "$project_dir/dist"
swiftc \
  "$project_dir/Sources/Battery/BatteryReading.swift" \
  "$project_dir/Sources/Devices/Compx/CompxCodec.swift" \
  "$project_dir/Tests/CompxCodecTests.swift" \
  -target arm64-apple-macos13.0 \
  -o "$out"
"$out"
```

chmod: `chmod +x test.sh`

- [ ] **Step 2: 运行测试，确认因缺少 CompxCodec 而失败**

Run: `./test.sh`

Expected: `error: cannot find 'CompxCodec' in scope`（或同等 swiftc 错误），exit ≠ 0。

- [ ] **Step 3: 实现 CompxCodec**

`Sources/Devices/Compx/CompxCodec.swift`:

```swift
import Foundation
import IOKit

enum CompxCodec {
    static let outputReportID: CFIndex = 0x08
    static let inputReportID: UInt32 = 0x08
    static let reportLength = 16
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

    static func parseBattery(reportID: UInt32, bytes: [UInt8]) -> BatteryReading? {
        guard reportID == inputReportID else { return nil }
        let payload = stripReportIDIfNeeded(bytes)
        guard payload.count > 6, payload[0] == cmdGetBattery else { return nil }
        let percent = Int(payload[5] & 0xFF)
        let isCharging = (payload[6] & 0xFF) != 0
        return BatteryReading(percent: percent, isCharging: isCharging)
    }

    static func parseVersion(reportID: UInt32, bytes: [UInt8]) -> (commandId: UInt8, version: String)? {
        guard reportID == inputReportID else { return nil }
        let payload = stripReportIDIfNeeded(bytes)
        guard payload.count > 6 else { return nil }
        guard payload[0] == cmdGetMouseVersion || payload[0] == cmdGetDongleVersion else { return nil }
        return (payload[0], String(format: "%X.%02X", payload[5], payload[6]))
    }
}
```

- [ ] **Step 4: 再跑测试**

Run: `./test.sh`

Expected: 打印 `CompxCodec tests passed`，exit 0。

- [ ] **Step 5: Commit**

```bash
git add Sources/Devices/Compx/CompxCodec.swift Tests/CompxCodecTests.swift test.sh
git commit -m "refactor: extract CompxCodec with checksum and parse tests"
```

---

### Task 3: HIDSession

**Files:**
- Create: `Sources/HID/HIDMatch.swift`
- Create: `Sources/HID/HIDSession.swift`

**Interfaces:**
- Consumes: `BridgeError`
- Produces:
  - `struct HIDMatch` — `vendorID: Int`, `productID: Int`, `usagePage: Int`, `usage: Int`
  - `struct HIDConnection` — `sendOutput(reportID:bytes:)`, `awaitInput(timeout:parse:)`
  - `enum HIDSession` — `static func withDevice<T>(_ match: HIDMatch, _ body: (HIDConnection) throws -> T) throws -> T`

本层不依赖 Compx。回调收到的原始 `(reportID, bytes)` 交给 `parse` 闭包。无真实硬件时不写 IOKit 单测；正确性靠编译 + Task 8 后的手动插拔。

- [ ] **Step 1: 写入 HIDMatch 与 HIDSession**

`Sources/HID/HIDMatch.swift`:

```swift
import Foundation

struct HIDMatch {
    let vendorID: Int
    let productID: Int
    let usagePage: Int
    let usage: Int
}
```

`Sources/HID/HIDSession.swift`:

```swift
import Foundation
import IOKit.hid

private final class QueryState {
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
    var parsed: Any?

    init() { buffer.initialize(repeating: 0, count: 256) }
    deinit { buffer.deinitialize(count: 256); buffer.deallocate() }
}

private func number(_ device: IOHIDDevice, _ key: CFString) -> Int? {
    guard let value = IOHIDDeviceGetProperty(device, key), CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
    return (value as! NSNumber).intValue
}

struct HIDConnection {
    private let device: IOHIDDevice
    private let state: QueryState

    fileprivate init(device: IOHIDDevice, state: QueryState) {
        self.device = device
        self.state = state
    }

    func sendOutput(reportID: CFIndex, bytes: [UInt8]) throws {
        let result = bytes.withUnsafeBytes {
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                reportID,
                $0.bindMemory(to: UInt8.self).baseAddress!,
                bytes.count
            )
        }
        guard result == kIOReturnSuccess else { throw BridgeError.send(result) }
    }

    func awaitInput<T>(timeout: TimeInterval, parse: (UInt32, [UInt8]) -> T?) throws -> T {
        state.parsed = nil
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            if let value = state.parsed as? T {
                return value
            }
        }
        throw BridgeError.noResponse(timeout)
    }

    fileprivate func handle(reportID: UInt32, bytes: [UInt8], parse: (UInt32, [UInt8]) -> Any?) {
        if let value = parse(reportID, bytes) {
            state.parsed = value
        }
    }
}

enum HIDSession {
    private static var deviceListPrinted = false

    static func withDevice<T>(_ match: HIDMatch, displayName: String, parse: @escaping (UInt32, [UInt8]) -> Any?, _ body: (HIDConnection) throws -> T) throws -> T {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey as String: match.vendorID,
            kIOHIDProductIDKey as String: match.productID
        ] as CFDictionary)
        let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerResult == kIOReturnSuccess else { throw BridgeError.open(managerResult) }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        if !deviceListPrinted {
            let list = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
            NSLog("IOHIDManagerCopyDevices: \(list.count) 个设备")
            for device in list {
                let vendorID = number(device, kIOHIDVendorIDKey as CFString) ?? 0
                let productID = number(device, kIOHIDProductIDKey as CFString) ?? 0
                let usagePage = number(device, kIOHIDPrimaryUsagePageKey as CFString) ?? 0
                let usage = number(device, kIOHIDPrimaryUsageKey as CFString) ?? 0
                NSLog("设备: VendorID=0x\(String(vendorID, radix: 16)), ProductID=0x\(String(productID, radix: 16)), UsagePage=0x\(String(usagePage, radix: 16)), Usage=0x\(String(usage, radix: 16))")
            }
            deviceListPrinted = true
        }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let receiver = devices.first(where: {
                  number($0, kIOHIDPrimaryUsagePageKey as CFString) == match.usagePage &&
                  number($0, kIOHIDPrimaryUsageKey as CFString) == match.usage
              }) else {
            throw BridgeError.noReceiver(displayName)
        }

        let openResult = IOHIDDeviceOpen(receiver, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else { throw BridgeError.open(openResult) }
        defer { IOHIDDeviceClose(receiver, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let state = QueryState()
        let retained = Unmanaged.passRetained(state)
        defer { retained.release() }

        let connection = HIDConnection(device: receiver, state: state)
        let callback: IOHIDReportCallback = { context, _, _, _, reportID, report, length in
            guard let context else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            box.connection.handle(reportID: reportID, bytes: bytes, parse: box.parse)
        }

        let box = CallbackBox(connection: connection, parse: parse)
        let boxRef = Unmanaged.passRetained(box)
        defer { boxRef.release() }

        IOHIDDeviceRegisterInputReportCallback(receiver, state.buffer, 256, callback, boxRef.toOpaque())
        IOHIDDeviceScheduleWithRunLoop(receiver, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        defer { IOHIDDeviceUnscheduleFromRunLoop(receiver, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue) }

        return try body(connection)
    }
}

private final class CallbackBox {
    let connection: HIDConnection
    let parse: (UInt32, [UInt8]) -> Any?

    init(connection: HIDConnection, parse: @escaping (UInt32, [UInt8]) -> Any?) {
        self.connection = connection
        self.parse = parse
    }
}
```

上面的 `parse: Any?` 能工作，但类型擦除别扭。实现时改用下面这个更干净的签名（以本段为准，覆盖上一段）：

```swift
enum HIDSession {
    private static var deviceListPrinted = false

    static func withDevice<T>(
        _ match: HIDMatch,
        displayName: String,
        _ body: (HIDConnection) throws -> T
    ) throws -> T {
        // matching / open / schedule 逻辑同上，但 callback 直接写入 QueryState 的闭包字段
        ...
    }
}

struct HIDConnection {
    func sendOutput(reportID: CFIndex, bytes: [UInt8]) throws
    func awaitInput<T>(timeout: TimeInterval, parse: @escaping (UInt32, [UInt8]) -> T?) throws -> T
}
```

推荐实现：`QueryState` 增加 `var onReport: ((UInt32, [UInt8]) -> Void)?`。C 回调只做 `state.onReport?(reportID, bytes)`。`awaitInput` 在等待前设置：

```swift
func awaitInput<T>(timeout: TimeInterval, parse: @escaping (UInt32, [UInt8]) -> T?) throws -> T {
    var result: T?
    state.onReport = { reportID, bytes in
        if let value = parse(reportID, bytes) {
            result = value
        }
    }
    defer { state.onReport = nil }
    let deadline = Date().addingTimeInterval(timeout)
    while result == nil && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    guard let result else { throw BridgeError.noResponse(timeout) }
    return result
}
```

C 回调：

```swift
private let inputCallback: IOHIDReportCallback = { context, _, _, _, reportID, report, length in
    guard let context else { return }
    let state = Unmanaged<QueryState>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: report, count: length))
    state.onReport?(reportID, bytes)
}
```

`withDevice` 只负责：匹配 VID/PID、按 usage 选接口、open、register callback、schedule runloop、`defer` 清理、执行 `body`。不要在 HIDSession 里解析电量。

完整应以「`onReport` 版本」落地，不要同时保留 `CallbackBox` 版本。

- [ ] **Step 2: 语法检查 HID 文件**

Run:

```bash
swiftc \
  Sources/Battery/BridgeError.swift \
  Sources/HID/HIDMatch.swift \
  Sources/HID/HIDSession.swift \
  -target arm64-apple-macos13.0 \
  -framework IOKit \
  -framework CoreFoundation \
  -parse-as-library \
  -typecheck
```

Expected: 无 error。若 `swiftc` 不接受 `-typecheck`，改为输出到 `/tmp/hid_typecheck.o` 并加空的 `enum HIDSessionTypecheck {}` 以外的入口；不要生成 app。

- [ ] **Step 3: Commit**

```bash
git add Sources/HID/HIDMatch.swift Sources/HID/HIDSession.swift
git commit -m "refactor: extract HIDSession for output/input report transport"
```

---

### Task 4: ATKA9Provider 并注册到 DeviceCatalog

**Files:**
- Create: `Sources/Devices/ATK/ATKA9Provider.swift`
- Modify: `Sources/Battery/BatteryProvider.swift`

**Interfaces:**
- Consumes: `BatteryProvider`, `DeviceIdentity`, `HIDSession`, `HIDMatch`, `CompxCodec`, `BridgeError`
- Produces:
  - `final class ATKA9Provider: BatteryProvider`
  - `DeviceCatalog.makeProviders() -> [ATKA9Provider()]`

行为对齐旧代码：

- `displayName = "ATK A9 Ultra Max三模"`
- `appName = "MouseBatteryBridge"`
- `accessoryIdentifier = "ATK-A9-2.4G"`
- `deviceType = "Mouse"`
- HID：VID `0x373B`，PID `0x11FE`，usagePage `0xFF05`，usage `0x00`
- 电源项 accessory PID `0x120F`
- `queryInterval = 10`，`timeout = 3`
- 第一次 `readBattery()` 在同一 `HIDSession.withDevice` 里先查鼠标/接收器版本并 `NSLog`，再查电量（避免旧代码的两次开关设备）

- [ ] **Step 1: 实现 ATKA9Provider**

`Sources/Devices/ATK/ATKA9Provider.swift`:

```swift
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
                NSLog("收到回包：\(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
                let reading = CompxCodec.parseBattery(reportID: reportID, bytes: bytes)
                if let reading {
                    NSLog("解析电量回包: percent=\(reading.percent), isCharging=\(reading.isCharging)")
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
            NSLog("%@: %@", label, parsed.version)
        } catch {
            NSLog("%@: 未收到有效响应", label)
        }
    }
}
```

`DeviceCatalog.makeProviders()` 改为：

```swift
enum DeviceCatalog {
    static func makeProviders() -> [BatteryProvider] {
        [ATKA9Provider()]
    }
}
```

- [ ] **Step 2: 编译 Provider 相关文件（无 main）**

Run:

```bash
swiftc \
  Sources/Battery/BatteryReading.swift \
  Sources/Battery/DeviceIdentity.swift \
  Sources/Battery/BridgeError.swift \
  Sources/Battery/BatteryProvider.swift \
  Sources/HID/HIDMatch.swift \
  Sources/HID/HIDSession.swift \
  Sources/Devices/Compx/CompxCodec.swift \
  Sources/Devices/ATK/ATKA9Provider.swift \
  -target arm64-apple-macos13.0 \
  -framework IOKit \
  -framework CoreFoundation \
  -parse-as-library \
  -typecheck
```

Expected: 无 error。

- [ ] **Step 3: Commit**

```bash
git add Sources/Devices/ATK/ATKA9Provider.swift Sources/Battery/BatteryProvider.swift
git commit -m "refactor: add ATKA9Provider and register it in DeviceCatalog"
```

---

### Task 5: PowerSource 改为吃 DeviceIdentity

**Files:**
- Create: `Sources/Publishers/PowerSource.swift`

**Interfaces:**
- Consumes: `DeviceIdentity`, `BatteryReading`, `BridgeError`
- Produces: `final class PowerSource` — `init() throws`, `func publish(identity: DeviceIdentity, reading: BatteryReading?) throws`

字段与旧实现一一对应：`Name` ← `displayName`，`Accessory Identifier` ← `accessoryIdentifier`，`Vendor ID` ← `receiverVendorID`，`Product ID` ← `accessoryProductID`。失败时仍由调用方决定不发布假 `0%`。

- [ ] **Step 1: 写入 PowerSource.swift**

```swift
import Foundation
import IOKit

private typealias PowerSourceID = UnsafeMutableRawPointer
@_silgen_name("IOPSCreatePowerSource") private func IOPSCreatePowerSource(_ source: UnsafeMutablePointer<PowerSourceID?>) -> IOReturn
@_silgen_name("IOPSSetPowerSourceDetails") private func IOPSSetPowerSourceDetails(_ source: PowerSourceID, _ details: CFDictionary) -> IOReturn
@_silgen_name("IOPSReleasePowerSource") private func IOPSReleasePowerSource(_ source: PowerSourceID) -> IOReturn

final class PowerSource {
    private var source: PowerSourceID?

    init() throws {
        let result = IOPSCreatePowerSource(&source)
        guard result == kIOReturnSuccess, source != nil else { throw BridgeError.powerSource(result) }
    }

    deinit {
        if let source { _ = IOPSReleasePowerSource(source) }
    }

    func publish(identity: DeviceIdentity, reading: BatteryReading?) throws {
        let details: [String: Any] = [
            "Name": identity.displayName,
            "Type": "Accessory Source",
            "Power Source State": "Battery Power",
            "Transport Type": "USB",
            "Accessory Category": identity.deviceType,
            "Accessory Identifier": identity.accessoryIdentifier,
            "Vendor ID": identity.receiverVendorID,
            "Product ID": identity.accessoryProductID,
            "Is Charging": reading?.isCharging ?? false,
            "Is Present": reading != nil,
            "Current Capacity": reading?.percent ?? 0,
            "Max Capacity": 100
        ]
        guard let source else { throw BridgeError.powerSource(kIOReturnNoDevice) }
        let result = IOPSSetPowerSourceDetails(source, details as CFDictionary)
        guard result == kIOReturnSuccess else { throw BridgeError.powerSource(result) }
    }
}
```

- [ ] **Step 2: typecheck**

Run:

```bash
swiftc \
  Sources/Battery/BatteryReading.swift \
  Sources/Battery/DeviceIdentity.swift \
  Sources/Battery/BridgeError.swift \
  Sources/Publishers/PowerSource.swift \
  -target arm64-apple-macos13.0 \
  -framework IOKit \
  -parse-as-library \
  -typecheck
```

Expected: 无 error。

- [ ] **Step 3: Commit**

```bash
git add Sources/Publishers/PowerSource.swift
git commit -m "refactor: parameterize PowerSource with DeviceIdentity"
```

---

### Task 6: NearcastSender 改为吃 DeviceIdentity

**Files:**
- Create: `Sources/Publishers/NearcastSender.swift`

**Interfaces:**
- Consumes: `DeviceIdentity`, `BatteryReading`
- Produces:
  - `final class NearcastSender`
  - `init?(groupID: String, identity: DeviceIdentity, requestRefresh: @escaping () -> Void)`
  - `func start()`
  - `func update(_ reading: BatteryReading)`
  - `func sendOffline() -> Bool`

协议字节、AES-GCM、service type `airbattery-nc`、groupID 规则 `nc-` 且长度 ≥ 23，全部原样搬迁。`MCPeerID.displayName` 用 `identity.displayName`；Nearcast `sender` 用 `identity.accessoryIdentifier`；`AirBatteryDevice` 的 `deviceID` / `deviceType` / `deviceName` / `deviceModel` 全部来自 `identity`。

- [ ] **Step 1: 从旧文件搬迁并替换 DeviceAdapter 引用**

把 `MouseBatteryBridge.swift` 中 `AirBatteryDevice`、`NearcastMessage`、`MultipeerEnvelope`、`NearcastSender` 整段拷到新文件。然后：

- `init` 增加 `identity: DeviceIdentity` 并存为 `private let identity`
- `MCPeerID(displayName: identity.displayName)`
- `AirBatteryDevice` 不再用默认值绑死设备名，改为：

```swift
private struct AirBatteryDevice: Encodable {
    let hasBattery: Bool
    let deviceID: String
    let deviceType: String
    let deviceName: String
    let deviceModel: String
    let batteryLevel: Int
    let isCharging: Int
    let isCharged = false
    let isPaused = false
    let acPowered = false
    let isHidden = false
    let lowPower = false
    let parentName = ""
    let lastUpdate: Double
    let realUpdate = 0.0
}
```

构造：

```swift
let device = AirBatteryDevice(
    hasBattery: hasBattery,
    deviceID: identity.accessoryIdentifier,
    deviceType: identity.deviceType,
    deviceName: identity.displayName,
    deviceModel: identity.displayName,
    batteryLevel: reading.percent,
    isCharging: reading.isCharging ? 1 : 0,
    lastUpdate: Date().timeIntervalSince1970
)
```

`NearcastMessage.sender` 用 `identity.accessoryIdentifier`。

- [ ] **Step 2: 确认旧符号不再出现在新文件**

Run: `rg "DeviceAdapter" Sources/Publishers/NearcastSender.swift`

Expected: 无匹配。

- [ ] **Step 3: Commit**

```bash
git add Sources/Publishers/NearcastSender.swift
git commit -m "refactor: parameterize NearcastSender with DeviceIdentity"
```

---

### Task 7: BatteryService

**Files:**
- Create: `Sources/Battery/BatteryService.swift`

**Interfaces:**
- Consumes: `BatteryProvider`, `DeviceCatalog`, `BridgeError`, `BatterySnapshot`
- Produces:
  - `final class BatteryService`
  - `init(providers: [BatteryProvider] = DeviceCatalog.makeProviders())`
  - `var queryInterval: TimeInterval { get }`
  - `func update() -> BatterySnapshot?`

选择规则：按 `providers` 顺序尝试 `readBattery()`。`BridgeError.noReceiver` 表示这只鼠标没插，继续下一个。其它错误只打日志并停止本轮（设备在但协议失败，不要误匹配下一只）。全部 `noReceiver` 则返回 `nil`，保留 `lastSnapshot` 但不对外返回新快照——调用方因此不会把电源项写成 `0%`。

- [ ] **Step 1: 写入 BatteryService.swift**

```swift
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

    func update() -> BatterySnapshot? {
        var sawNonReceiverError = false
        for provider in providers {
            do {
                let reading = try provider.readBattery()
                let snapshot = BatterySnapshot(identity: provider.identity, reading: reading)
                lastSnapshot = snapshot
                return snapshot
            } catch BridgeError.noReceiver(let name) {
                NSLog("%@: 未找到接收器 %@", provider.identity.appName, name)
            } catch {
                sawNonReceiverError = true
                NSLog("%@: %@", provider.identity.appName, "\(error)")
                break
            }
        }
        if !sawNonReceiverError {
            NSLog("MouseBatteryBridge: 未匹配到已连接的鼠标接收器")
        }
        return nil
    }
}
```

- [ ] **Step 2: typecheck（含 catalog / provider）**

Run:

```bash
swiftc \
  Sources/Battery/*.swift \
  Sources/HID/*.swift \
  Sources/Devices/Compx/CompxCodec.swift \
  Sources/Devices/ATK/ATKA9Provider.swift \
  -target arm64-apple-macos13.0 \
  -framework IOKit \
  -framework CoreFoundation \
  -parse-as-library \
  -typecheck
```

Expected: 无 error。zsh 下 `Sources/Battery/*.swift` 能展开；若不能，显式列出 Task 1/4/7 的文件。

- [ ] **Step 3: Commit**

```bash
git add Sources/Battery/BatteryService.swift
git commit -m "refactor: add BatteryService to select first matching provider"
```

---

### Task 8: App 接线，删除单文件入口

**Files:**
- Create: `Sources/App/AppDelegate.swift`
- Create: `Sources/App/main.swift`
- Delete: `MouseBatteryBridge.swift`
- Modify: `build.sh`

**Interfaces:**
- Consumes: `BatteryService`, `PowerSource`, `NearcastSender`, `DeviceIdentity`
- Produces: 可运行的 `dist/MouseBatteryBridge.app`

菜单、权限、开机启动、Nearcast group key `nearcastGroupID`、启动立即查一次、5 秒后若仍无读数再查一次、`applicationWillTerminate` 发离线，全部保持。

- [ ] **Step 1: 写 AppDelegate 与 main**

`Sources/App/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

`Sources/App/AppDelegate.swift` 从旧 `AppDelegate` 搬迁，差异如下：

```swift
import AppKit
import IOKit.hid
import ServiceManagement

private let nearcastGroupKey = "nearcastGroupID"

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let batteryService = BatteryService()
    private var timer: Timer?
    private var powerSource: PowerSource?
    private var nearcast: NearcastSender?
    private var lastSnapshot: BatterySnapshot?
    private var launchItem: NSMenuItem?
    private var permissionItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu()
        menu.delegate = self
        let permission = NSMenuItem(title: permissionTitle, action: #selector(requestInputMonitoring), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)
        permissionItem = permission
        let launch = NSMenuItem(title: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(launch)
        launchItem = launch
        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MouseBatteryBridge")
        statusItem.button?.image?.isTemplate = true

        startNearcastIfConfigured()
        DispatchQueue.main.async { [weak self] in self?.updateBattery() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.lastSnapshot == nil else { return }
            self.updateBattery()
        }
        timer = Timer.scheduledTimer(withTimeInterval: batteryService.queryInterval, repeats: true) { [weak self] _ in
            self?.updateBattery()
        }
    }

    private var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    private var inputMonitoringGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    private var permissionTitle: String { inputMonitoringGranted ? "输入监控授权（已授权）" : "输入监控授权…" }

    func menuWillOpen(_ menu: NSMenu) {
        permissionItem?.title = permissionTitle
        permissionItem?.isEnabled = !inputMonitoringGranted
        launchItem?.state = launchAtLoginEnabled ? .on : .off
    }

    @objc private func requestInputMonitoring() {
        guard !inputMonitoringGranted else { return }
        if IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) { return }
        let alert = NSAlert()
        alert.messageText = "需要输入监控权限"
        alert.informativeText = "请在系统设置的“隐私与安全性 → 输入监控”中允许 MouseBatteryBridge。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后处理")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
            launchItem?.state = launchAtLoginEnabled ? .on : .off
        } catch {
            NSLog("MouseBatteryBridge: \(error)")
        }
    }

    private func updateBattery() {
        guard let snapshot = batteryService.update() else { return }
        lastSnapshot = snapshot
        do {
            if powerSource == nil { powerSource = try PowerSource() }
            try powerSource?.publish(identity: snapshot.identity, reading: snapshot.reading)
            startNearcastIfConfigured()
            nearcast?.update(snapshot.reading)
        } catch {
            NSLog("MouseBatteryBridge: \(error)")
        }
    }

    private func startNearcastIfConfigured() {
        guard nearcast == nil,
              let groupID = UserDefaults.standard.string(forKey: nearcastGroupKey),
              let identity = lastSnapshot?.identity ?? batteryService.lastSnapshot?.identity
        else { return }
        guard let sender = NearcastSender(groupID: groupID, identity: identity, requestRefresh: refreshAirBattery) else { return }
        nearcast = sender
        sender.start()
        if let lastSnapshot { sender.update(lastSnapshot.reading) }
    }

    private func refreshAirBattery() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.openAirBatteryRefresh()
        }
    }

    private func openAirBatteryRefresh() {
        guard let url = URL(string: "airbattery://reloadwingets") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            if let error { NSLog("AirBattery 后台刷新失败：\(error)") }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard nearcast?.sendOffline() == true else { return }
        Thread.sleep(forTimeInterval: 0.3)
        openAirBatteryRefresh()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
```

`startNearcastIfConfigured` 在第一次成功读数之前没有 identity。保持与旧行为一致：读数成功后再 `startNearcastIfConfigured()`（`updateBattery` 里已有这次调用）。因此把 `applicationDidFinishLaunching` 里那次 `startNearcastIfConfigured()` 留着也可以——没有 identity 就 return。不要在无 identity 时用 ATK 名字硬编码造 Nearcast peer。

- [ ] **Step 2: 改 build.sh 编译全部 Sources**

把 `swiftc "$project_dir/MouseBatteryBridge.swift"` 换成：

```zsh
setopt null_glob
swift_files=("$project_dir"/Sources/**/*.swift)
if (( ${#swift_files[@]} == 0 )); then
  echo "no Swift sources under Sources/" >&2
  exit 1
fi

swiftc "${swift_files[@]}" \
  -target arm64-apple-macos13.0 \
  -framework AppKit \
  -framework IOKit \
  -framework CoreFoundation \
  -framework MultipeerConnectivity \
  -framework ServiceManagement \
  -o "$app/Contents/MacOS/MouseBatteryBridge"
```

不要把 `Tests/` 编进 app。`build.sh` 已是 zsh（`#/bin/zsh`），`**` glob 可用。

- [ ] **Step 3: 删除旧单文件**

```bash
rm MouseBatteryBridge.swift
```

确认仓库里不再有第二份 `AppDelegate` / `main`。

- [ ] **Step 4: 构建**

Run: `./build.sh`

Expected: 打印 `.../dist/MouseBatteryBridge.app`，exit 0。

Run: `./test.sh`

Expected: `CompxCodec tests passed`。

- [ ] **Step 5: Commit**

```bash
git add Sources/App/AppDelegate.swift Sources/App/main.swift build.sh
git rm MouseBatteryBridge.swift
git commit -m "refactor: split app entry from device adapters"
```

---

### Task 9: README 改成「加一只鼠标怎么做」

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: 本计划的目录与协议
- Produces: 与 ATK A9 代码一致的说明；删掉仍写 JZM5 VID/PID 的过时段落，或明确标成「历史模板」

- [ ] **Step 1: 更新 README 的适配章节**

把「适配其他鼠标」改成：

1. 新建 `Sources/Devices/<Vendor>/<Name>Provider.swift`，实现 `BatteryProvider`。
2. 若协议是 Compx 同类（Output `0x08` + 16 字节 command），复用 `CompxCodec`，只换 `HIDMatch` 和 `DeviceIdentity`。
3. 若只是字节布局不同但仍是 Output + Input Report，新建 `*Codec.swift`，继续用 `HIDSession`。
4. 若改为 Feature Report / 广播 / BLE，不要改 `HIDSession`，在 Provider 内自己取电。
5. 在 `DeviceCatalog.makeProviders()` 追加实例。数组顺序 = 匹配优先级。
6. `./test.sh`（有 codec 测试时）和 `./build.sh`。

保留：输入监控、Nearcast `defaults write local.atka9.MouseBatteryBridge nearcastGroupID ...`（以 `Info.plist` 的 `CFBundleIdentifier` = `local.atka9.MouseBatteryBridge` 为准，不要再写 `local.jzm5.batterytray`）。

- [ ] **Step 2: 对照 Info.plist 检查 Bundle ID / 显示名**

`Info.plist` 保持：

- `CFBundleIdentifier` = `local.atka9.MouseBatteryBridge`
- `CFBundleDisplayName` = `MouseBatteryBridge for ATK A9 Ultra Max三模`

README 启动、权限、Nearcast 命令必须用这个 Bundle ID。

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: describe BatteryProvider layout for adding mice"
```

---

## 加鼠标清单（实现完成后用）

新建设备时最小骨架：

```swift
final class OtherMouseProvider: BatteryProvider {
    let identity = DeviceIdentity(
        displayName: "...",
        appName: "MouseBatteryBridge",
        accessoryIdentifier: "...",
        deviceType: "Mouse",
        receiverVendorID: 0x0000,
        accessoryProductID: 0x0000
    )
    let queryInterval: TimeInterval = 10
    let timeout: TimeInterval = 3

    func readBattery() throws -> BatteryReading {
        try HIDSession.withDevice(match, displayName: identity.displayName) { connection in
            try connection.sendOutput(reportID: ..., bytes: ...)
            return try connection.awaitInput(timeout: timeout) { reportID, bytes in
                // parse → BatteryReading?
                nil
            }
        }
    }
}
```

然后：`DeviceCatalog.makeProviders() -> [ATKA9Provider(), OtherMouseProvider()]`。

---

## 手动验收

硬件插着 ATK A9 2.4G 接收器时：

1. `./test.sh` 通过。
2. `./build.sh` 产出 app。
3. 启动后菜单栏有鼠标图标；授权输入监控后日志出现电量回包。
4. 系统电池组件出现「ATK A9 Ultra Max三模」。
5. 拔接收器：不把电量写成 0%；插回后恢复。
6. 若配置了 `nearcastGroupID`，AirBattery 仍能收到电量。
7. 退出 app 后系统电源项消失。

---

## Self-review

1. **Spec coverage:** 方案 B 的协议边界、HID 会话、Compx 编解码、发布器参数化、单设备优先匹配、build.sh 多文件、加鼠标路径，均有对应 Task。
2. **Placeholder scan:** HIDSession 以 `onReport` 版本为准，已标明不要落地 `CallbackBox` 双实现。
3. **Type consistency:** `BatteryProvider` 为 class protocol；`DeviceCatalog.makeProviders()` 返回 `[BatteryProvider]`；`PowerSource.publish(identity:reading:)` 与 `NearcastSender.init(groupID:identity:requestRefresh:)` 使用同一 `DeviceIdentity`。
