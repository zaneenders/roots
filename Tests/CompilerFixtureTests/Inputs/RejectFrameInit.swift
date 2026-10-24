import Roots
// expected-error: 'UIFrame' initializer is inaccessible due to 'internal' protection level

@MainActor func invalid() { _ = UIFrame() }
