import Foundation
import IOKit.hid

private final class QueryState {
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
    var onReport: ((UInt32, [UInt8]) -> Void)?

    init() { buffer.initialize(repeating: 0, count: 256) }
    deinit { buffer.deinitialize(count: 256); buffer.deallocate() }
}

private func number(_ device: IOHIDDevice, _ key: CFString) -> Int? {
    guard let value = IOHIDDeviceGetProperty(device, key), CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
    return (value as! NSNumber).intValue
}

private let inputCallback: IOHIDReportCallback = { context, _, _, _, reportID, report, length in
    guard let context else { return }
    let state = Unmanaged<QueryState>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: report, count: length))
    state.onReport?(reportID, bytes)
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
}

enum HIDSession {
    private static var deviceListPrinted = false

    static func withDevice<T>(
        _ match: HIDMatch,
        displayName: String,
        _ body: (HIDConnection) throws -> T
    ) throws -> T {
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
            MBLog.log("IOHIDManagerCopyDevices: \(list.count) 个设备")
            for device in list {
                let vendorID = number(device, kIOHIDVendorIDKey as CFString) ?? 0
                let productID = number(device, kIOHIDProductIDKey as CFString) ?? 0
                let usagePage = number(device, kIOHIDPrimaryUsagePageKey as CFString) ?? 0
                let usage = number(device, kIOHIDPrimaryUsageKey as CFString) ?? 0
                MBLog.log("设备: VendorID=0x\(String(vendorID, radix: 16)), ProductID=0x\(String(productID, radix: 16)), UsagePage=0x\(String(usagePage, radix: 16)), Usage=0x\(String(usage, radix: 16))")
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

        IOHIDDeviceRegisterInputReportCallback(receiver, state.buffer, 256, inputCallback, retained.toOpaque())
        IOHIDDeviceScheduleWithRunLoop(receiver, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        defer { IOHIDDeviceUnscheduleFromRunLoop(receiver, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue) }

        return try body(HIDConnection(device: receiver, state: state))
    }
}
