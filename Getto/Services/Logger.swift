import AppKit
import Foundation
import os

/// Log debug terpusat; bisa dibuka lewat menu Bantuan → Tampilkan Log.
enum Logger {
    private static let log = OSLog(subsystem: "com.getto.app", category: "getto")
    private static var buffer: [String] = []
    private static let lock = NSLock()
    private static let maxLines = 1000

    static func log(_ message: String) {
        os_log("%{public}@", log: log, message)
        lock.lock()
        let stamp = ISO8601DateFormatter().string(from: Date())
        buffer.append("[\(stamp)] \(message)")
        if buffer.count > maxLines { buffer.removeFirst(buffer.count - maxLines) }
        lock.unlock()
    }

    static func recentLines() -> String {
        lock.lock(); defer { lock.unlock() }
        return buffer.joined(separator: "\n")
    }

    static var logFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Getto/getto.log")
    }

    static func revealLog() {
        let url = logFileURL
        try? recentLines().write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
    }
}
