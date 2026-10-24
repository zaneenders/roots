#!/usr/bin/env swift
import Foundation
import Glibc

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

struct RunFailure: Error, CustomStringConvertible {
  let description: String
  var status: Int32 = 1
}

@MainActor func executable(_ name: String, environment: [String: String]) throws -> URL {
  for directory in (environment["PATH"] ?? "").split(
    separator: ":", omittingEmptySubsequences: false)
  {
    let path = URL(fileURLWithPath: directory.isEmpty ? "." : String(directory))
      .appendingPathComponent(name)
    if FileManager.default.isExecutableFile(atPath: path.path) { return path }
  }
  throw RunFailure(description: "missing required command: \(name)")
}

func forwardLog(_ input: FileHandle, to output: FileHandle = .standardOutput) {
  while let data = try? input.read(upToCount: 16_384), !data.isEmpty { output.write(data) }
}

func report(_ message: String) {
  FileHandle.standardError.write(Data((message + "\n").utf8))
}

@MainActor func send(_ signal: Int32, to process: Process) {
  guard process.isRunning else { return }
  let pid = process.processIdentifier
  // Foundation gives children their own process groups. Include compiler/test descendants.
  _ = kill(getpgid(pid) == pid ? -pid : pid, signal)
}

@MainActor func stop(_ process: Process, grace: Duration = .seconds(5)) async {
  // Cleanup must finish even when the task driving the run has been cancelled.
  await Task { @MainActor in
    send(SIGTERM, to: process)
    let deadline = ContinuousClock.now.advanced(by: grace)
    while process.isRunning, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(50))
    }
    send(SIGKILL, to: process)
    process.waitUntilExit()
  }.value
}

@MainActor func launch(
  _ executable: URL, arguments: [String], environment: [String: String], log: URL
) throws -> Process {
  try Data().write(to: log)
  let output = try FileHandle(forWritingTo: log)
  defer { try? output.close() }
  let process = Process()
  process.executableURL = executable
  process.arguments = arguments
  process.environment = environment
  process.currentDirectoryURL = root
  process.standardInput = FileHandle.nullDevice
  process.standardOutput = output
  process.standardError = output
  try process.run()
  return process
}

@MainActor func wait(_ process: Process, timeout: Duration, log: URL) async throws {
  let input = try FileHandle(forReadingFrom: log)
  defer {
    forwardLog(input)
    try? input.close()
  }
  let deadline = ContinuousClock.now.advanced(by: timeout)
  do {
    while process.isRunning {
      forwardLog(input)
      try Task.checkCancellation()
      guard ContinuousClock.now < deadline else {
        throw RunFailure(description: "command timed out", status: 124)
      }
      try await Task.sleep(for: .milliseconds(20))
    }
    try Task.checkCancellation()
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw RunFailure(
        description: "command exited with status \(process.terminationStatus)",
        status: process.terminationReason == .exit ? process.terminationStatus : 1)
    }
  } catch {
    await stop(process, grace: .seconds(10))
    throw error
  }
}

@MainActor func run() async throws {
  var environment = ProcessInfo.processInfo.environment
  let swift = try executable("swift", environment: environment)
  guard let seconds = Double(environment["ROOTS_TEST_TIMEOUT"] ?? "180"),
    seconds.isFinite, seconds > 0
  else { throw RunFailure(description: "ROOTS_TEST_TIMEOUT must be a positive number of seconds") }

  let artifacts = root.appendingPathComponent(
    ".build/compositor-tests/current.\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
  report(
    "Testing current Wayland session (\(environment["XDG_CURRENT_DESKTOP"] ?? "unknown compositor")); logs: \(artifacts.path)"
  )
  defer { report("Compositor test artifacts: \(artifacts.path)") }

  // Connect by display path without consuming an inherited activation socket.
  environment.removeValue(forKey: "WAYLAND_SOCKET")
  environment["ROOTS_REQUIRE_COMPOSITOR"] = "1"
  environment["ROOTS_REQUIRE_PRESENTATION"] = environment["ROOTS_REQUIRE_PRESENTATION"] ?? "0"
  let log = artifacts.appendingPathComponent("tests.log")
  let tests = try launch(
    swift,
    arguments: [
      "test", "--filter", "CompositorIntegrationTests|NativeSessionTests|SwiftWaylandTests",
    ],
    environment: environment, log: log)
  try await wait(tests, timeout: .seconds(seconds), log: log)
}

guard
  CommandLine.arguments.count == 1
    || (CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "current")
else {
  report("usage: swift Scripts/test-compositors.swift [current]")
  exit(2)
}

// Top-level state is MainActor-isolated; signal handlers enqueue updates on that actor.
var interrupted: Int32?
let task = Task { @MainActor in
  do {
    try await run()
    return Int32(0)
  } catch is CancellationError {
    return interrupted ?? 130
  } catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    return (error as? RunFailure)?.status ?? 1
  }
}
var signals: [DispatchSourceSignal] = []
for number in [SIGINT, SIGTERM] {
  _ = signal(number, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
  source.setEventHandler {
    Task { @MainActor in
      if interrupted == nil { interrupted = 128 + number }
      task.cancel()
    }
  }
  source.resume()
  signals.append(source)
}
let status = await task.value
for source in signals { source.cancel() }
exit(status)
