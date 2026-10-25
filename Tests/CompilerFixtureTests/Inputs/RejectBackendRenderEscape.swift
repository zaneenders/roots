import Roots

// expected-error: assigning non-escaping parameter 'render' to an '@escaping' closure

@MainActor
final class InvalidBackendClient {
  var retainedRender: (@MainActor (borrowing UIDrawBatch) -> Void)?
  func connect(_ backend: any DesktopBackend) async throws {
    try await backend.run(configuration: .init(title: "Invalid")) { _, render in
      self.retainedRender = render
    }
  }
}
