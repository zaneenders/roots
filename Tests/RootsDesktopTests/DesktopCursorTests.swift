import Roots
import Testing

@testable import RootsDesktop

@MainActor
struct DesktopCursorTests {
  @Test(arguments: [CursorShape.crosshair, .eastWestResize, .grabbing, .default])
  func overridesSurviveAutomaticUpdatesUntilCleared(shape: CursorShape) {
    var applied: [CursorShape] = []
    let cursors = DesktopCursors { shape, _ in
      applied.append(shape)
      return true
    }
    #expect(cursors.set(shape, popup: false))
    for style: CursorStyle in [.default, .pointer, .text] {
      cursors.update(style, popup: false)
      #expect(applied.last == shape)
    }
    #expect(cursors.set(nil, popup: false))
    #expect(applied.last == .text)
    cursors.update(.pointer, popup: false)
    #expect(applied.last == .pointer)
  }

  @Test func overridesAndResetsArePerSurface() {
    var applied: [Bool: CursorShape] = [:]
    let cursors = DesktopCursors { shape, popup in
      applied[popup] = shape
      return true
    }
    #expect(cursors.set(.crosshair, popup: false))
    #expect(cursors.set(.grabbing, popup: true))
    cursors.update(.pointer, popup: false)
    cursors.update(.text, popup: true)
    #expect(applied == [false: .crosshair, true: .grabbing])

    cursors.reset(popup: true)
    #expect(cursors.set(nil, popup: true))
    #expect(applied == [false: .crosshair, true: .default])
    cursors.update(.text, popup: true)
    #expect(applied[true] == .text)
    #expect(cursors.set(nil, popup: false))
    #expect(applied[false] == .pointer)
  }

  @Test func unavailableBackendStillRecordsCursorIntent() {
    var applied: CursorShape?
    let cursors = DesktopCursors { shape, _ in
      applied = shape
      return false
    }
    #expect(!cursors.set(.crosshair, popup: false))
    cursors.update(.text, popup: false)
    #expect(applied == .crosshair)
    #expect(!cursors.set(nil, popup: false))
    #expect(applied == .text)
  }
}

#if os(Linux)
@testable import WaylandBridge

extension DesktopWindowRenderingTests {
  @Test(arguments: [false, true])
  func explicitCursorSurvivesFrameCallbacksAndSubsequentFrames(popup: Bool) throws {
    let previous = DesktopSystem.cursors
    var applied: [Bool: CursorShape] = [:]
    DesktopSystem.cursors = DesktopCursors { shape, popup in
      applied[popup] = shape
      return true
    }
    defer { DesktopSystem.cursors = previous }

    var frames = 0
    let runtime = DesktopRuntime(
      content: { viewport in
        Column(in: viewport.bounds, gap: 0) {
          Button(key: 1, "Button", extent: 40)
          Text("Text").selectable(key: 2).frame(height: .fixed(40))
        }
      }, primaryShortcut: .control, onCopy: { _ in }, requestRedraw: {},
      frameCallbacks: .init(finish: { _ in
        if frames == 0 { #expect(DesktopSystem.setCursor(.crosshair, popup: popup)) }
      }))
    defer { runtime.stop() }

    let expectedStyles: [CursorStyle] = [.default, .pointer, .text, .pointer, .default]
    let positions: [Float] = [90, 10, 60, 10, 90]
    try NativeWindow.run(
      configuration: .init(width: 100, height: 100, maxFrames: 5), surfaceless: true
    ) { snapshot, renderer in
      var snapshot = snapshot
      snapshot.pointerInside = true
      snapshot.pointerX = 10
      snapshot.pointerY = positions[frames]
      DesktopSystem.frame(
        snapshot.backendFrame, render: { renderer.render($0) }, runtime: runtime, popup: popup)
      #expect(runtime.cursorStyle == expectedStyles[frames])
      let expected: CursorShape = frames < 3 ? .crosshair : frames == 3 ? .pointer : .eastWestResize
      #expect(applied[popup] == expected)
      #expect(applied[!popup] == nil)
      if frames == 2 {
        #expect(DesktopSystem.setCursor(nil, popup: popup))
        #expect(applied[popup] == .text)
      } else if frames == 3 {
        #expect(DesktopSystem.setCursor(.eastWestResize, popup: popup))
      }
      frames += 1
    }
    #expect(frames == 5)
  }

  @Test func cursorOverridesDoNotLeakIntoLaterWindowSessions() async throws {
    let previous = DesktopSystem.cursors
    var applied: [Bool: CursorShape] = [:]
    DesktopSystem.cursors = DesktopCursors { shape, popup in
      applied[popup] = shape
      return true
    }
    defer { DesktopSystem.cursors = previous }

    #expect(DesktopSystem.setCursor(.crosshair))
    #expect(DesktopSystem.setCursor(.grabbing, popup: true))
    let window = DesktopWindow("Cursor", width: 16, height: 16, maxFrames: 1, offscreen: true) { _ in
      BlockBuilder.buildBlock()
    }
    try await window.run()
    #expect(applied[false] == .crosshair)
    #expect(DesktopSystem.setCursor(nil, popup: true))
    #expect(applied[true] == .default)
    try await window.run()
    #expect(applied[false] == .default)
  }
}
#endif
