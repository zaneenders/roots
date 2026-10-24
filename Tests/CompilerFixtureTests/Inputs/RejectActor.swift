import Roots
// expected-error: call to main actor-isolated initializer 'init(_:)' in a synchronous nonisolated context

func invalid() { _ = Text("off actor") }
