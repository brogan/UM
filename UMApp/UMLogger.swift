import Foundation
import AppKit

// nonisolated(unsafe): written once on main actor at startup, then read-only
// from the C exception handler. The write and the handler can't overlap.
nonisolated(unsafe) private var _umLogFD: Int32 = -1

/// Synchronous crash-safe logger. Writes to ~/Library/Logs/UM/UM_YYYY-MM-DD.log.
/// FileHandle.write is unbuffered — bytes reach the kernel immediately, so the log
/// survives a force-quit or Swift fatal error up to the last written line.
@MainActor
final class UMLogger {

    static let shared = UMLogger()

    private var fd: Int32 = -1          // same fd mirrored in _umLogFD for the exception handler
    private(set) var logURL: URL
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library")
        let dir = base.appendingPathComponent("Logs/UM")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        logURL = dir.appendingPathComponent("UM_\(dayFmt.string(from: Date())).log")

        fd = open(logURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        _umLogFD = fd
        write("=== UM session started \(Date()) ===")

        // Obj-C exception handler: no context capture allowed in C function pointer,
        // so fd is read from the file-scope _umLogFD global.
        // Swift fatal errors (index out of range) are not catchable, but the log
        // up to that line will already be on disk.
        NSSetUncaughtExceptionHandler { ex in
            let msg = "[UNCAUGHT EXCEPTION] \(ex.name.rawValue): \(ex.reason ?? "nil")\n"
                + ex.callStackSymbols.prefix(20).joined(separator: "\n") + "\n"
            if let data = msg.data(using: .utf8) {
                data.withUnsafeBytes { _ = Darwin.write(_umLogFD, $0.baseAddress!, $0.count) }
            }
        }
    }

    func log(_ msg: String, file: String = #fileID, line: Int = #line) {
        let ts   = Self.timeFmt.string(from: Date())
        let src  = (file as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
        write("[\(ts)] \(src):\(line)  \(msg)")
    }

    func logState(prefix: String, layers: Int, styles: Int, cells: Int,
                  file: String = #fileID, line: Int = #line) {
        log("\(prefix) — \(layers)L \(styles)S \(cells)C", file: file, line: line)
    }

    func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    private func write(_ line: String) {
        let out = line + "\n"
        print(out, terminator: "")
        guard fd >= 0, let data = out.data(using: .utf8) else { return }
        data.withUnsafeBytes { _ = Darwin.write(fd, $0.baseAddress!, $0.count) }
    }

    deinit {
        if fd >= 0 { Darwin.close(fd) }
    }
}
