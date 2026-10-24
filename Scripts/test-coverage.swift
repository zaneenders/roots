#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

@discardableResult
func run(_ arguments: [String], captureOutput: Bool = false) throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = arguments
  process.currentDirectoryURL = root
  process.standardError = FileHandle.standardError
  let pipe = captureOutput ? Pipe() : nil
  if let pipe {
    process.standardOutput = pipe
  } else {
    process.standardOutput = FileHandle.standardOutput
  }
  try process.run()
  let previousHandler = signal(SIGINT, SIG_IGN)
  let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
  interrupt.setEventHandler {
    if process.isRunning { process.interrupt() }
  }
  interrupt.resume()
  defer {
    interrupt.cancel()
    signal(SIGINT, previousHandler)
  }
  let output = pipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
  process.waitUntilExit()
  guard process.terminationReason == .exit, process.terminationStatus == 0 else {
    exit(process.terminationReason == .exit ? process.terminationStatus : 1)
  }
  return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

do {
  try run(["swift", "test", "--enable-code-coverage"])
  let path = try run(["swift", "test", "--show-codecov-path"], captureOutput: true)
  let coverage = URL(fileURLWithPath: path).deletingLastPathComponent()
  let binaries = try FileManager.default.contentsOfDirectory(
    at: coverage.deletingLastPathComponent(), includingPropertiesForKeys: nil
  ).compactMap { entry -> String? in
    #if os(macOS)
    guard entry.pathExtension == "xctest" else { return nil }
    return entry.appendingPathComponent("Contents/MacOS/\(entry.deletingPathExtension().lastPathComponent)").path
    #else
    return entry.pathExtension == "xctest" || entry.lastPathComponent.hasSuffix("Tests.so") ? entry.path : nil
    #endif
  }.sorted()
  guard let binary = binaries.first else {
    FileHandle.standardError.write(Data("error: No test binaries found.\n".utf8))
    exit(1)
  }
  #if os(macOS)
  let llvmCov = ["xcrun", "llvm-cov"]
  #else
  let llvmCov = ["llvm-cov"]
  #endif
  try run(
    llvmCov + ["report", binary]
      + binaries.dropFirst().flatMap { ["-object", $0] }
      + [
        "--instr-profile=\(coverage.appendingPathComponent("default.profdata").path)",
        "--ignore-filename-regex=(\\.build/|Tests/)"
      ])
} catch {
  FileHandle.standardError.write(Data("error: \(error)\n".utf8))
  exit(1)
}
