@MainActor
public protocol RootsApp {
  init() throws
  associatedtype MainWindow: Window
  var window: MainWindow { get }
}

extension RootsApp {
  public static func main() async throws {
    let app = try Self()
    defer { withExtendedLifetime(app) {} }
    try await app.window.run()
  }
}

@MainActor
public protocol Window {
  func run() async throws
}
