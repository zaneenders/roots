#!/usr/bin/env swift
import Foundation
import Glibc
import Synchronization

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

func printLog(_ path: URL, to output: FileHandle = .standardOutput) {
  guard let input = try? FileHandle(forReadingFrom: path) else { return }
  defer { try? input.close() }
  while let data = try? input.read(upToCount: 16_384), !data.isEmpty { output.write(data) }
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

@MainActor func wait(_ process: Process, timeout: Duration) async throws {
  let deadline = ContinuousClock.now.advanced(by: timeout)
  do {
    while process.isRunning {
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

@MainActor func run(_ mode: String) async throws {
  var environment = ProcessInfo.processInfo.environment
  let swift = try executable("swift", environment: environment)
  let binary = mode == "current" ? nil : try executable(mode, environment: environment)
  if mode == "sway" { _ = try executable("swaymsg", environment: environment) }
  guard let seconds = Double(environment["ROOTS_TEST_TIMEOUT"] ?? "180"),
    seconds.isFinite, seconds > 0
  else { throw RunFailure(description: "ROOTS_TEST_TIMEOUT must be a positive number of seconds") }

  let artifacts = root.appendingPathComponent(
    ".build/compositor-tests/\(mode).\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
  var runtime: URL?
  var compositor: Process?
  let compositorLog = artifacts.appendingPathComponent("compositor.log")
  let testsLog = artifacts.appendingPathComponent("tests.log")
  defer {
    if let runtime { try? FileManager.default.removeItem(at: runtime) }
    print("Compositor test artifacts: \(artifacts.path)")
  }

  do {
    // Never inherit an activation socket, including in current-session mode.
    environment.removeValue(forKey: "WAYLAND_SOCKET")
    if let binary {
      let directory = URL(fileURLWithPath: "/tmp/roots-wayland.\(UUID().uuidString)")
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      runtime = directory
      environment["XDG_RUNTIME_DIR"] = directory.path
      for key in ["WAYLAND_DISPLAY", "DISPLAY", "SWAYSOCK", "HYPRLAND_INSTANCE_SIGNATURE"] {
        environment.removeValue(forKey: key)
      }
      let renderer = environment["ROOTS_TEST_RENDERER"] ?? "pixman"
      let arguments: [String]
      if mode == "sway" {
        let config = artifacts.appendingPathComponent("sway.conf")
        try "xwayland disable\noutput * resolution 800x600 scale 1\nseat * hide_cursor 1000\n"
          .write(to: config, atomically: true, encoding: .utf8)
        environment["WLR_BACKENDS"] = "headless"
        environment["WLR_HEADLESS_OUTPUTS"] = "1"
        environment["WLR_LIBINPUT_NO_DEVICES"] = "1"
        environment["WLR_RENDERER"] = renderer
        arguments = ["--unsupported-gpu", "--config", config.path]
      } else {
        let versionLog = artifacts.appendingPathComponent("version.log")
        let version = try launch(
          binary, arguments: ["--version"], environment: environment, log: versionLog)
        try await wait(version, timeout: .seconds(5))
        let text = try String(contentsOf: versionLog, encoding: .utf8)
        guard let major = text.split(whereSeparator: { !$0.isNumber }).first.flatMap({ Int($0) })
        else { throw RunFailure(description: "cannot parse Weston version: \(text)") }
        // Weston renamed the headless renderer options in version 12.
        let option =
          major >= 12
          ? "--renderer=\(renderer)"
          : (renderer == "pixman" ? "--use-pixman" : "--use-gl")
        arguments = [
          "--backend=headless-backend.so", option, "--shell=kiosk-shell.so", "--no-config",
          "--socket=wayland-roots-test", "--idle-time=0", "--width=800", "--height=600",
        ]
      }
      let process = try launch(
        binary, arguments: arguments, environment: environment, log: compositorLog)
      compositor = process
      let deadline = ContinuousClock.now.advanced(by: .seconds(10))
      while environment["WAYLAND_DISPLAY"] == nil {
        try Task.checkCancellation()
        guard process.isRunning else {
          throw RunFailure(description: "\(mode) exited before opening a Wayland socket")
        }
        guard ContinuousClock.now < deadline else {
          throw RunFailure(description: "timed out waiting for \(mode)")
        }
        for socket in try FileManager.default.contentsOfDirectory(atPath: directory.path)
        where socket.hasPrefix("wayland-") {
          let path = directory.appendingPathComponent(socket).path
          let attributes = try FileManager.default.attributesOfItem(atPath: path)
          if attributes[.type] as? FileAttributeType == .typeSocket {
            environment["WAYLAND_DISPLAY"] = socket
            break
          }
        }
        if environment["WAYLAND_DISPLAY"] == nil { try await Task.sleep(for: .milliseconds(100)) }
      }
      if mode == "sway" {
        environment["SWAYSOCK"] =
          "\(directory.path)/sway-ipc.\(getuid()).\(process.processIdentifier).sock"
      }
    }
    environment["ROOTS_TEST_COMPOSITOR"] = mode
    environment["ROOTS_REQUIRE_COMPOSITOR"] = "1"
    environment["ROOTS_REQUIRE_PRESENTATION"] = environment["ROOTS_REQUIRE_PRESENTATION"] ?? "0"
    let tests = try launch(
      swift,
      arguments: [
        "test", "--filter", "CompositorIntegrationTests|NativeSessionTests|SwiftWaylandTests",
      ],
      environment: environment, log: testsLog)
    try await wait(tests, timeout: .seconds(seconds))
    if let compositor, !compositor.isRunning {
      throw RunFailure(description: "\(mode) exited during the tests")
    }
    printLog(testsLog)
    if let compositor { await stop(compositor) }
  } catch {
    printLog(testsLog)
    printLog(compositorLog, to: .standardError)
    if let compositor { await stop(compositor) }
    throw error
  }
}

let mode = CommandLine.arguments.dropFirst().first ?? "all"
guard CommandLine.arguments.count <= 2, ["all", "sway", "weston", "current"].contains(mode) else {
  FileHandle.standardError.write(
    Data("usage: swift Scripts/test-compositors.swift [all|sway|weston|current]\n".utf8))
  exit(2)
}

let interrupted = Mutex<Int32?>(nil)
let task = Task { @MainActor in
  do {
    for mode in mode == "all" ? ["sway", "weston"] : [mode] { try await run(mode) }
    return Int32(0)
  } catch is CancellationError {
    return interrupted.withLock { $0 ?? 130 }
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
    interrupted.withLock { if $0 == nil { $0 = 128 + number } }
    task.cancel()
  }
  source.resume()
  signals.append(source)
}
let status = await task.value
for source in signals { source.cancel() }
exit(status)
