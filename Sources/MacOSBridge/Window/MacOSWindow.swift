import AppKit
import Foundation
import Roots

@MainActor public enum MacOSWindow {
  private static var host: MacOSWindowHost?
  private static let clipboardLimit = 16 * 1024 * 1024

  public static func requestRedraw() { host?.requestRedraw() }

  @discardableResult
  public static func setCursor(_ shape: CursorShape) -> Bool {
    host?.view.setCursor(shape) ?? false
  }

  @available(*, noasync, message: "Use runAsync from an asynchronous context")
  public static func run(
    configuration: WindowConfiguration = WindowConfiguration(),
    frame: @escaping @MainActor (WindowFrameInput, inout MetalRenderFrame) -> Void
  ) throws {
    let session = try start(configuration: configuration, frame: frame)
    defer { stop(session) }
    session.host.show()
    NSApplication.shared.run()
    if let error = session.host.error { throw error }
  }

  public static func runAsync(
    configuration: WindowConfiguration = WindowConfiguration(),
    frame: @escaping @MainActor (WindowFrameInput, inout MetalRenderFrame) -> Void
  ) async throws {
    try Task.checkCancellation()
    let session = try start(configuration: configuration, frame: frame)
    defer { stop(session) }
    let windowHost = session.host
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        RunLoop.main.perform(inModes: [.default]) {
          MainActor.assumeIsolated {
            if !windowHost.finished {
              windowHost.show()
              NSApplication.shared.run()
            }
            continuation.resume()
          }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
      }
    } onCancel: {
      Task { @MainActor in windowHost.requestClose() }
    }
    try Task.checkCancellation()
    if let error = windowHost.error { throw error }
  }

  private struct Session {
    let host: MacOSWindowHost
    let delegate: MacOSApplicationDelegate
    let previousDelegate: (any NSApplicationDelegate)?
    let previousMenu: NSMenu?
  }

  private static func start(
    configuration: WindowConfiguration,
    frame: @escaping @MainActor (WindowFrameInput, inout MetalRenderFrame) -> Void
  ) throws -> Session {
    guard host == nil else { throw MacOSWindowError.alreadyRunning }
    let size = configuration.logicalSize
    guard size.x.isFinite, size.y.isFinite, size.x > 0, size.y > 0,
      size.x <= 8192, size.y <= 8192, configuration.maxFrames >= 0,
      configuration.screenshotPath == nil || configuration.maxFrames > 0
    else { throw MacOSWindowError.invalidConfiguration }
    if let minimum = configuration.minimumSize {
      guard minimum.x.isFinite, minimum.y.isFinite, minimum.x >= 0, minimum.y >= 0,
        minimum.x <= size.x, minimum.y <= size.y
      else { throw MacOSWindowError.invalidConfiguration }
    }
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    let delegate = MacOSApplicationDelegate()
    let session = try MacOSWindowHost(configuration: configuration, frame: frame)
    host = session
    delegate.host = session
    let previousDelegate = application.delegate
    let previousMenu = application.mainMenu
    application.delegate = delegate
    let menu = NSMenu()
    let item = NSMenuItem()
    let appMenu = NSMenu(title: configuration.title)
    appMenu.addItem(
      withTitle: "About \(configuration.title)",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: "")
    appMenu.addItem(.separator())
    let quit = appMenu.addItem(
      withTitle: "Quit \(configuration.title)",
      action: #selector(MacOSApplicationDelegate.quit(_:)), keyEquivalent: "q"
    )
    quit.target = delegate
    item.submenu = appMenu
    menu.addItem(item)
    application.mainMenu = menu
    return Session(
      host: session, delegate: delegate, previousDelegate: previousDelegate,
      previousMenu: previousMenu)
  }

  private static func stop(_ session: Session) {
    session.host.cleanup()
    host = nil
    NSApplication.shared.delegate = session.previousDelegate
    NSApplication.shared.mainMenu = session.previousMenu
  }

  public static func requestClose() { host?.requestClose() }

  public static func readClipboard() async -> String? {
    guard !Task.isCancelled, let value = NSPasteboard.general.string(forType: .string),
      value.utf8.count <= clipboardLimit
    else { return nil }
    return value
  }

  @discardableResult public static func writeClipboard(_ text: String) -> Bool {
    guard text.utf8.count <= clipboardLimit else { return false }
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(text, forType: .string)
  }

  public static func renderOffscreen(
    configuration: WindowConfiguration = WindowConfiguration(maxFrames: 12),
    frame: @MainActor (WindowFrameInput, inout MetalRenderFrame) -> Void
  ) async throws {
    let size = configuration.logicalSize
    guard size.x.isFinite, size.y.isFinite, size.x > 0, size.y > 0,
      size.x <= 8192, size.y <= 8192, configuration.maxFrames > 0
    else { throw MacOSWindowError.invalidConfiguration }
    try Task.checkCancellation()
    let drawableSize = SIMD2<Int32>(Int32(size.x.rounded(.up)), Int32(size.y.rounded(.up)))
    let renderer = try MetalRenderer(logicalSize: size, drawableSize: drawableSize)
    for index in 0..<configuration.maxFrames {
      try Task.checkCancellation()
      let snapshot = WindowFrameInput(
        logicalSize: size, drawableSize: drawableSize, timeSeconds: Double(index) / 60)
      let readback = index == configuration.maxFrames - 1 && configuration.screenshotPath != nil
      let image = try await renderer.render(readback: readback) { renderFrame in
        frame(snapshot, &renderFrame)
      }
      if let image, let path = configuration.screenshotPath {
        try image.write(to: URL(fileURLWithPath: path))
      }
    }
  }
}
