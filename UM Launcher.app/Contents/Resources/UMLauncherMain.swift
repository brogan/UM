import Foundation

let projectDir = "/Users/broganbunt/UMApp"
let scheme     = "UMApp"
let buildDir   = "/tmp/umapp-build"
let appPath    = "\(buildDir)/\(scheme).app"
let logPath    = "/tmp/um-launcher.log"

func appendLog(_ msg: String) {
    let line = "\(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: logPath),
       let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    } else {
        try? data.write(to: URL(fileURLWithPath: logPath))
    }
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
appendLog("Building \(scheme)...")

let status = run("/usr/bin/xcodebuild", [
    "-scheme", scheme,
    "-destination", "platform=macOS",
    "CONFIGURATION_BUILD_DIR=\(buildDir)",
    "build"
])

guard status == 0 else {
    appendLog("xcodebuild failed (status \(status)). Check /tmp/um-launcher.log")
    exit(status)
}

appendLog("Launching \(appPath)...")
let openStatus = run("/usr/bin/open", [appPath])
appendLog("open finished with status \(openStatus).")
exit(openStatus)
