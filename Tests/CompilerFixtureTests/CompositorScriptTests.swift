#if os(Linux)
  import Foundation
  import Glibc
  import Testing

  @Test func compositorScriptRunsInSwiftInterpreter() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: log)
    defer { try? FileManager.default.removeItem(at: log) }
    let output = try FileHandle(forWritingTo: log)
    defer { try? output.close() }
    let process = Process()
    if let compiler = ProcessInfo.processInfo.environment["SWIFT_EXEC"] {
      process.executableURL = URL(fileURLWithPath: compiler).deletingLastPathComponent()
        .appendingPathComponent("swift")
      process.arguments = ["Scripts/test-compositors.swift", "invalid"]
    } else {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = ["swift", "Scripts/test-compositors.swift", "invalid"]
    }
    process.currentDirectoryURL = root
    process.standardOutput = output
    process.standardError = output
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    guard finished.wait(timeout: .now() + 30) == .success else {
      if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
      process.waitUntilExit()
      Issue.record("Swift interpreter timed out")
      return
    }
    process.waitUntilExit()
    let diagnostics = try String(contentsOf: log, encoding: .utf8)
    #expect(process.terminationReason == .exit, "\(diagnostics)")
    #expect(process.terminationStatus == 2, "\(diagnostics)")
    #expect(diagnostics.contains("usage: swift Scripts/test-compositors.swift"), "\(diagnostics)")
  }
#endif
