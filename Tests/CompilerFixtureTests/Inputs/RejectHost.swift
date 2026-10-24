import Roots
// expected-error: cannot find 'UIHost' in scope

@MainActor func invalid() { _ = UIHost() }
