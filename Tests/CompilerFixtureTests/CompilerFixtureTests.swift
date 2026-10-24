import Foundation
import Testing

#if os(macOS)
  import Darwin
#else
  import Glibc
#endif

@Test func compilerFixturesEnforceThePublicAPIAndLifetimes() throws {
  let fixtures = try #require(Bundle.module.url(forResource: "Inputs", withExtension: nil))
  let files = try FileManager.default.contentsOfDirectory(
    at: fixtures, includingPropertiesForKeys: nil
  ).filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
  try #require(files.contains { $0.lastPathComponent == "Client.swift" })
  try #require(files.contains { $0.lastPathComponent == "Components.swift" })
  let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: scratch) }

  var arguments = [
    "-swift-version", "6", "-enable-experimental-feature", "Lifetimes",
    "-strict-memory-safety", "-warnings-as-errors",
    "-I", try rootsModuleDirectory().path, "-I", scratch.path,
  ]
  #if os(macOS)
    // Match the package's deployment target when importing its built module.
    #if arch(arm64)
      arguments += ["-target", "arm64-apple-macosx27.0"]
    #elseif arch(x86_64)
      arguments += ["-target", "x86_64-apple-macosx27.0"]
    #endif
  #endif
  let components = try compileFixture(
    arguments + [
      "-emit-module", "-c", "-module-name", "BlockFixtureComponents",
      "-emit-module-path",
      scratch.appendingPathComponent("BlockFixtureComponents.swiftmodule").path,
      fixtures.appendingPathComponent("Components.swift").path,
      "-o", scratch.appendingPathComponent("Components.o").path,
    ], in: scratch)
  try #require(components.status == 0, "Components.swift: \(components.diagnostics)")

  for file in files where file.lastPathComponent != "Components.swift" {
    let source = try String(contentsOf: file, encoding: .utf8)
    let marker = "// expected-error: "
    let expectedErrors = source.split(separator: "\n").compactMap { line in
      line.hasPrefix(marker) ? String(line.dropFirst(marker.count)) : nil
    }
    let rejecting = file.lastPathComponent.hasPrefix("Reject")
    try #require(
      rejecting == !expectedErrors.isEmpty,
      "Missing or misplaced expected-error marker in \(file.lastPathComponent)")
    // Type checking alone misses ownership diagnostics emitted during SIL generation.
    let result = try compileFixture(
      arguments + ["-c", file.path, "-o", scratch.appendingPathComponent("fixture.o").path],
      in: scratch)
    if rejecting {
      #expect(result.status != 0, "\(file.lastPathComponent) unexpectedly compiled")
      for expected in expectedErrors {
        #expect(
          result.diagnostics.contains(": error: " + expected),
          "\(file.lastPathComponent) did not produce '\(expected)':\n\(result.diagnostics)")
      }
    } else {
      #expect(result.status == 0, "\(file.lastPathComponent):\n\(result.diagnostics)")
    }
  }
}

private func rootsModuleDirectory() throws -> URL {
  // Swift Build puts modules beside the resource bundle; the legacy SwiftPM
  // build system uses a Modules subdirectory. Ascend for macOS test bundles.
  for startingPoint in [Bundle.module.bundleURL, Bundle.main.bundleURL] {
    var directory = startingPoint.deletingLastPathComponent()
    for _ in 0..<8 {
      for candidate in [directory, directory.appendingPathComponent("Modules")] {
        if FileManager.default.fileExists(
          atPath: candidate.appendingPathComponent("Roots.swiftmodule").path)
        {
          return candidate
        }
      }
      directory.deleteLastPathComponent()
    }
  }
  throw FixtureError.missingRootsModule
}

private enum FixtureError: Error { case missingRootsModule, compilerTimedOut, compilerCrashed }

private func compileFixture(_ arguments: [String], in scratch: URL) throws -> (
  status: Int32, diagnostics: String
) {
  let process = Process()
  if let compiler = ProcessInfo.processInfo.environment["SWIFT_EXEC"] {
    process.executableURL = URL(fileURLWithPath: compiler)
    process.arguments = arguments
  } else {
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swiftc"] + arguments
  }
  // Preserve the checkout's toolchain selection when swiftc is a Swiftly shim.
  process.currentDirectoryURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let log = scratch.appendingPathComponent("compiler.log")
  try Data().write(to: log)
  let output = try FileHandle(forWritingTo: log)
  defer { try? output.close() }
  process.standardOutput = output
  process.standardError = output
  let finished = DispatchSemaphore(value: 0)
  process.terminationHandler = { _ in finished.signal() }
  try process.run()
  guard finished.wait(timeout: .now() + 30) == .success else {
    if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
    process.waitUntilExit()
    throw FixtureError.compilerTimedOut
  }
  process.waitUntilExit()
  guard process.terminationReason == .exit else { throw FixtureError.compilerCrashed }
  return (process.terminationStatus, try String(contentsOf: log, encoding: .utf8))
}
