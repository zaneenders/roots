import Roots
// expected-error: 'state' cannot be captured by an escaping closure since it is a borrowed parameter

@MainActor func invalid(_ state: borrowing UIState) {
  Task { _ = state.state(for: 1) }
}
