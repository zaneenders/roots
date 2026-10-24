import DesktopTestSupport
import Foundation
import SwiftWayland
import Testing

@testable import WaylandBridge

@MainActor private func withDeadline(
  _ operation: @escaping @MainActor @Sendable () async throws -> Void
) async throws {
  try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask { try await operation() }
    group.addTask {
      try await Task.sleep(for: .seconds(10))
      throw CompositorTestError.timeout
    }
    defer { group.cancelAll() }
    _ = try await group.next()
  }
}

private enum CompositorTestError: Error { case timeout }

@Suite(GraphicsTest(), .serialized, .timeLimit(.minutes(1)))
@MainActor struct CompositorIntegrationTests {
  @Test func requiredCompositorCapabilities() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["ROOTS_REQUIRE_COMPOSITOR"] == "1" else { return }
    let globals = try await WaylandAvailability.advertisedGlobals
    #expect(try await WaylandAvailability.compositor)
    for name in globals.keys.sorted() {
      print("Wayland global: \(name) v\(globals[name]!)")
    }
    if environment["ROOTS_REQUIRE_PRESENTATION"] == "1" {
      #expect(try await WaylandAvailability.presentation)
    }
  }

  @Test(.enabled("Wayland compositor is unavailable") { try await WaylandAvailability.compositor })
  func configureDrainAndReconnectWithoutGPU() async throws {
    try await withDeadline {
      for _ in 0..<3 {
        let connection = WaylandConnection(configuration: .init(width: 160, height: 120))
        do {
          try await connection.connect()
          #expect(connection.configured && connection.running)
          try await connection.drain()
          connection.requestClose()
          #expect(connection.protocolFailure == nil)
          await connection.close()
          await connection.close()
          #expect(!connection.running && !connection.configured)
        } catch {
          await connection.close()
          throw error
        }
      }
    }
  }

  @Test(
    .enabled("Wayland dma-buf presentation is unavailable") {
      try await WaylandAvailability.presentation
    })
  func presentParentAndPopupIndependentlyThenReconnect() async throws {
    try await withDeadline {
      for _ in 0..<2 {
        let host = NativeHost(configuration: .init(width: 160, height: 120))
        do {
          try await host.connect()
          try host.setupRenderer(surfaceless: false)
          var parentFrames: Int32 = 0
          let started = ContinuousClock.now
          while parentFrames < 3 && host.running {
            try Task.checkCancellation()
            if host.canRender {
              _ = try NativeWindow.renderFrame(
                host, surfaceless: false, started: started, frameCount: &parentFrames,
                frame: { _, _ in host.requestRedraw() })
              try host.renderer.releaseCurrent()
            } else {
              try await host.dispatchAsync()
            }
          }
          try #require(parentFrames == 3)
          // Settle pending configure/feedback before counting popup-only frames.
          try await host.drain()
          for _ in 0..<3 {
            host.connection.waitForDMABufBuffer()
            let before = parentFrames
            var popupFrames = 0
            var dismissals = 0
            try host.presentPopup(
              configuration: .init(
                x: 0, y: 0, anchorWidth: 10, anchorHeight: 10, width: 64, height: 48),
              grab: false,
              frame: { _, _ in
                popupFrames += 1
                host.requestPopupRedraw()
              }, onDismiss: { dismissals += 1 })
            while popupFrames < 3 && host.running && host.connection.popupInput != nil {
              try Task.checkCancellation()
              if host.canRender {
                host.connection.waitForDMABufBuffer()
                _ = try NativeWindow.renderFrame(
                  host, surfaceless: false, started: started, frameCount: &parentFrames,
                  frame: { _, _ in })
                try host.renderer.releaseCurrent()
              } else {
                try await host.dispatchAsync()
              }
            }
            try #require(popupFrames == 3)
            host.dismissPopup()
            host.dismissPopup()
            try await host.drain()
            #expect(dismissals == 1 && host.connection.popupInput == nil)
            #expect(parentFrames == before)
          }
          #expect(host.connection.protocolFailure == nil)
          await host.close()
        } catch {
          await host.close()
          throw error
        }
      }
    }
  }
}
