import Roots
// expected-error: extra argument 'key' in call

@MainActor
func invalid() { _ = Text("Display text", key: 1) }
