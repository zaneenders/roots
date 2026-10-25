import AppKit
import DesktopTestSupport
import Foundation
import Roots
import Testing

@testable import MacOSBridge

@Suite(
  GraphicsTest(), .serialized,
  .enabled("Metal or a WindowServer session is unavailable") { await GraphicsAvailability.window })
@MainActor struct MacOSWindowTests {
  @Test func windowRendersResizesTranslatesEventsAndWritesRetinaScreenshot() async throws {
    await Task.yield()
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(UUID().uuidString).ppm")
    defer { try? FileManager.default.removeItem(at: path) }
    var frames = 0
    try await MacOSWindow.runAsync(
      configuration: .init(
        logicalSize: .init(420, 320), title: "Window test", maxFrames: 8, screenshotPath: path.path)
    ) {
      snapshot, frame in
      frames += 1
      #expect(snapshot.timeSeconds == Double(frames - 1) / 60)
      let view =
        NSApplication.shared.windows.first(where: { $0.title == "Window test" })?.contentView
        as? MacOSInputView
      guard let view, let host = view.host else {
        Issue.record("Missing native view")
        return
      }
      if frames == 1 {
        #expect(throws: MacOSWindowError.alreadyRunning) {
          try MacOSWindow.run { _, _ in }
        }
        let key = NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
          windowNumber: host.window.windowNumber, context: nil, characters: "a",
          charactersIgnoringModifiers: "a",
          isARepeat: false, keyCode: 0)!
        view.keyDown(with: key)
        host.input.pointer(x: 15, y: 25, inside: true)
        host.input.button(down: true)
        host.input.scroll(x: 1, y: 2)
        host.window.setContentSize(NSSize(width: 600, height: 400))
      } else if frames == 2 {
        #expect(
          snapshot.input.keyEvents == [
            KeyEvent(.character("a"), modifiers: .super, physicalCode: 0)
          ])
        #expect(snapshot.input.pressed && snapshot.input.mousePosition == Coordinate(x: 15, y: 25))
        #expect(snapshot.input.scrollY == 2 && snapshot.input.scrollVelocityY == nil)
        host.input.pointer(x: -20, y: 500, inside: false)
        host.input.button(down: false)
      } else if frames == 3 {
        #expect(snapshot.input.released && snapshot.input.mousePosition == Coordinate(x: -20, y: 500))
        #expect(!snapshot.input.pressed && snapshot.input.keyEvents.isEmpty)
      } else if frames >= 4 {
        #expect(snapshot.logicalSize == .init(600, 400))
        #expect(snapshot.drawableSize.x >= 600 && snapshot.drawableSize.y >= 400)
        #expect(!snapshot.input.released && snapshot.input.mousePosition == nil)
      }
      let draws = [
        DrawRect(Region(0, 0, snapshot.logicalSize.x, snapshot.logicalSize.y), Color(0, 1, 0))
      ]
      frame.render(draws.span)
    }
    #expect(frames == 8)
    let image = try Data(contentsOf: path)
    let header = String(decoding: image.prefix(32), as: UTF8.self)
    #expect(header.hasPrefix("P6\n600 400\n255\n") || header.hasPrefix("P6\n1200 800\n255\n"))
  }

  @Test func menuQuitDrainsInflightFramesAndSessionCanReopen() async throws {
    var frames = 0
    try await MacOSWindow.runAsync(
      configuration: .init(logicalSize: .init(420, 320), title: "Quit test")
    ) { _, frame in
      frames += 1
      let draws = [DrawRect(Region(0, 0, 420, 320), Color(1, 0, 0))]
      frame.render(draws.span)
      if frames < 3 { MacOSWindow.requestRedraw() }
      if frames == 3 {
        let menu = NSApplication.shared.mainMenu!.items[0].submenu!
        // AppKit can append system menu items. Invoke our quit command explicitly.
        let quit = menu.items.first { $0.action == #selector(MacOSApplicationDelegate.quit(_:)) }!
        menu.performActionForItem(at: menu.index(of: quit))
      }
    }
    #expect(frames == 3)
    var reopened = 0
    try await MacOSWindow.runAsync(configuration: .init(logicalSize: .init(420, 320), maxFrames: 2)) { _, _ in
      reopened += 1
    }
    #expect(reopened == 2)
  }

  @Test func windowCloseAndScreenshotFailureReturnWithoutLeakingSession() async throws {
    var frames = 0
    try await MacOSWindow.runAsync(
      configuration: .init(logicalSize: .init(420, 320), title: "Close test")
    ) { _, _ in
      frames += 1
      let window = NSApplication.shared.windows.first(where: { $0.title == "Close test" })!
      window.performClose(nil)
    }
    #expect(frames == 1)
    await #expect(throws: CocoaError.self) {
      try await MacOSWindow.runAsync(
        configuration: .init(logicalSize: .init(420, 320), maxFrames: 1, screenshotPath: "/tmp")
      ) {
        _, _ in
      }
    }
    try await MacOSWindow.runAsync(configuration: .init(logicalSize: .init(420, 320), maxFrames: 1)) { _, _ in }
  }

  @Test func idleWindowPausesAndCoalescesRedrawRequests() async throws {
    var frames = 0
    let driver = Task { @MainActor in
      while frames == 0 { try await Task.sleep(for: .milliseconds(1)) }
      try await Task.sleep(for: .milliseconds(300))
      let view =
        NSApplication.shared.windows.first(where: { $0.title == "Idle test" })?.contentView
        as? MacOSInputView
      #expect(view?.isPaused == true)
      let settled = frames
      try await Task.sleep(for: .milliseconds(100))
      #expect(frames == settled)
      for _ in 0..<20 { MacOSWindow.requestRedraw() }
      try await Task.sleep(for: .milliseconds(100))
      #expect(frames == settled + 1)
      #expect(view?.isPaused == true)
      MacOSWindow.requestClose()
    }
    defer { driver.cancel() }
    try await MacOSWindow.runAsync(
      configuration: .init(logicalSize: .init(420, 320), title: "Idle test")
    ) { _, _ in
      frames += 1
    }
  }

  @Test func cancellationDrainsFramesAndAllowsAnotherSession() async throws {
    var frames = 0
    let task = Task { @MainActor in
      try await MacOSWindow.runAsync(configuration: .init(logicalSize: .init(420, 320))) { _, _ in
        frames += 1
        MacOSWindow.requestRedraw()
      }
    }
    while frames < 2 { try await Task.sleep(for: .milliseconds(1)) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    var reopened = 0
    try await MacOSWindow.runAsync(configuration: .init(logicalSize: .init(420, 320), maxFrames: 2)) { _, _ in
      reopened += 1
    }
    #expect(reopened == 2)
  }

  @Test func cancellationBeforeStartupDoesNotInvokeFrames() async throws {
    let task = Task { @MainActor in
      try await MacOSWindow.runAsync { _, _ in Issue.record("Cancelled session invoked a frame") }
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    try await MacOSWindow.runAsync(configuration: .init(logicalSize: .init(420, 320), maxFrames: 1)) { _, _ in }
  }

  @Test func clipboardRoundTripsTextAndBoundsPublication() async throws {
    let pasteboard = NSPasteboard.general
    let saved: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map {
      item in
      Dictionary(
        uniqueKeysWithValues: item.types.compactMap { type in
          item.data(forType: type).map { (type, $0) }
        })
    }
    defer {
      pasteboard.clearContents()
      pasteboard.writeObjects(
        saved.map { values in
          let item = NSPasteboardItem()
          for (type, data) in values { item.setData(data, forType: type) }
          return item
        })
    }
    #expect(MacOSWindow.writeClipboard("café\nsecond line"))
    #expect(await MacOSWindow.readClipboard() == "café\nsecond line")
    #expect(!MacOSWindow.writeClipboard(String(repeating: "x", count: 16 * 1024 * 1024 + 1)))
    #expect(await MacOSWindow.readClipboard() == "café\nsecond line")
  }
}

extension MacOSWindowTests {
  @Test func backendNormalizesAuxiliaryInputAndAppliesNativeWindowOptions() async throws {
    let backend = MacOSBackend()
    var frames = 0
    try await backend.run(
      configuration: .init(
        title: "Backend contract", logicalSize: .init(width: 420, height: 320),
        minimumSize: .init(width: 200, height: 150), maxFrames: 3)
    ) { snapshot, _ in
      frames += 1
      guard let window = NSApplication.shared.windows.first(where: { $0.title == "Backend contract" }),
        let view = window.contentView as? MacOSInputView
      else {
        Issue.record("Missing backend window")
        return
      }
      #expect(window.contentMinSize == NSSize(width: 200, height: 150))
      #expect(snapshot.logicalSize == Size(width: 420, height: 320))
      #expect(snapshot.scale >= 1)
      if frames == 1 {
        let event = NSEvent.mouseEvent(
          with: .rightMouseDown, location: .init(x: 10, y: 10), modifierFlags: [], timestamp: 0,
          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        view.rightMouseDown(with: event)
        #expect(backend.setCursor(.text))
        #expect(!backend.setCursor(.wait))
      } else if frames == 2 {
        #expect(snapshot.input.secondaryPressed && snapshot.input.secondaryDown)
        #expect(!snapshot.input.pressed && snapshot.input.mousePosition != nil)
        let event = NSEvent.mouseEvent(
          with: .rightMouseUp, location: .init(x: 10, y: 10), modifierFlags: [], timestamp: 0,
          windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
        view.rightMouseUp(with: event)
      } else {
        #expect(snapshot.input.secondaryReleased && !snapshot.input.secondaryDown)
        #expect(!snapshot.input.secondaryPressed && !snapshot.input.released)
      }
    }
    #expect(frames == 3)
    #expect(!backend.setCursor(.text))
  }
}
