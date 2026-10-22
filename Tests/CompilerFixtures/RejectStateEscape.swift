import Roots

@MainActor func invalid(_ state: borrowing UIState) {
  Task { _ = state.state(for: 1) }
}
