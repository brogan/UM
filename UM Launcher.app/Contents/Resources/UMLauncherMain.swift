import Foundation
import AppKit

let projectDir  = "/Users/broganbunt/UMApp"
let scheme      = "UMApp"
let buildDir    = "/tmp/umapp-build"
let appPath     = "\(buildDir)/\(scheme).app"
let binaryPath  = "\(appPath)/Contents/MacOS/\(scheme)"
let logPath     = "/tmp/um-launcher.log"
let appBundleID = "org.brogan.umapp"
let savedStatePath = "\(NSHomeDirectory())/Library/Saved Application State/\(appBundleID).savedState"

// Directories whose modification times are checked to decide whether a rebuild is needed.
let sourceRoots = [
    "\(projectDir)/UMApp",
    "\(projectDir)/UMEngine/Sources",
]

func newestMtime(in roots: [String]) -> Date? {
    let fm = FileManager.default
    var newest: Date? = nil
    for root in roots {
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { continue }
        for case let url as URL in enumerator {
            guard let ext = url.pathExtension.lowercased() as String?,
                  ["swift", "xcdatamodeld", "xcassets", "storyboard", "plist"].contains(ext) else { continue }
            if let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                if newest == nil || mtime > newest! { newest = mtime }
            }
        }
    }
    return newest
}

func binaryMtime() -> Date? {
    (try? URL(fileURLWithPath: binaryPath)
        .resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate)
}

func needsRebuild() -> Bool {
    guard let binary = binaryMtime() else { return true }   // no binary yet
    guard let sources = newestMtime(in: sourceRoots) else { return true }
    return sources > binary
}

func appendLog(_ msg: String) {
    let line = "\(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: logPath),
       let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    } else {
        try? data.write(to: URL(fileURLWithPath: logPath))
    }
}

func showAlert(title: String, message: String) {
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

@discardableResult
func run(_ exe: String, _ args: [String], env: [String: String]? = nil) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    p.currentDirectoryURL = URL(fileURLWithPath: projectDir)
    if let env { p.environment = env }
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError  = pipe
    pipe.fileHandleForReading.readabilityHandler = { h in
        let d = h.availableData
        if !d.isEmpty, let t = String(data: d, encoding: .utf8) {
            appendLog(t.trimmingCharacters(in: .newlines))
        }
    }
    do { try p.run(); p.waitUntilExit() }
    catch { appendLog("Failed to run \(exe): \(error)"); return 1 }
    pipe.fileHandleForReading.readabilityHandler = nil
    return p.terminationStatus
}

appendLog("==== \(Date()) ====")

if needsRebuild() {
    appendLog("Source changes detected — building \(scheme)...")
    let status = run("/usr/bin/xcodebuild", [
        "-scheme", scheme,
        "-destination", "platform=macOS",
        "CONFIGURATION_BUILD_DIR=\(buildDir)",
        "build"
    ])
    guard status == 0 else {
        let message = "The UM build failed with status \(status). Details were written to \(logPath)."
        appendLog("xcodebuild failed (status \(status)). Check \(logPath)")
        showAlert(title: "UM could not be built", message: message)
        exit(status)
    }
} else {
    appendLog("No source changes — skipping build.")
}

let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID)
if !runningApps.isEmpty {
    appendLog("Terminating \(runningApps.count) running UM instance(s)...")
    for app in runningApps {
        app.terminate()
    }
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline && runningApps.contains(where: { !$0.isTerminated }) {
        Thread.sleep(forTimeInterval: 0.1)
    }
for app in runningApps where !app.isTerminated {
        appendLog("Force terminating stale UM instance pid \(app.processIdentifier)...")
        app.forceTerminate()
    }
}

if FileManager.default.fileExists(atPath: savedStatePath) {
    do {
        try FileManager.default.removeItem(atPath: savedStatePath)
        appendLog("Removed saved app state at \(savedStatePath)")
    } catch {
        appendLog("Could not remove saved app state at \(savedStatePath): \(error)")
    }
}

appendLog("Launching \(appPath)...")
let openStatus = run("/usr/bin/open", ["-n", appPath])
appendLog("open finished with status \(openStatus).")
if openStatus != 0 {
    showAlert(title: "UM could not be opened",
              message: "The app was built, but macOS could not open \(appPath). Details were written to \(logPath).")
}
exit(openStatus)
