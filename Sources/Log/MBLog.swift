import Foundation
import os

enum MBLog {
    static let logURL = URL(fileURLWithPath: NSString(string: "~/Library/Logs/MouseBatteryBridge.log").expandingTildeInPath)
    private static let logger = Logger(subsystem: "local.atka9.MouseBatteryBridge", category: "bridge")
    private static let queue = DispatchQueue(label: "local.atka9.MouseBatteryBridge.log")
    private static let maxBytes = 1024 * 1024
    private static let trimTargetBytes = maxBytes / 2

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func log(_ message: String) {
        logger.log("\(message, privacy: .public)")
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async { append(line) }
    }

    private static func append(_ line: String) {
        let url = logURL
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
        trimIfNeeded()
    }

    private static func trimIfNeeded() {
        guard let content = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        var size = content.utf8.count
        guard size > maxBytes else { return }
        var lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        while size > trimTargetBytes, !lines.isEmpty {
            size -= lines.removeFirst().utf8.count + 1
        }
        try? ((lines.joined(separator: "\n") + "\n").data(using: .utf8)?.write(to: logURL, options: .atomic))
    }
}
