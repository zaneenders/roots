import Roots
// expected-error: cannot find 'Focus' in scope
// expected-error: cannot find 'ScrollTo' in scope

@MainActor func invalid() {
  _ = Focus(key: 1)
  _ = ScrollTo(10, in: 1)
}
