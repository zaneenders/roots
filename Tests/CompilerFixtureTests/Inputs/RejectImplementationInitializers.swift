import Roots
// expected-error: '_Empty' initializer is inaccessible due to 'internal' protection level
// expected-error: '_Pair<First, Next>' initializer is inaccessible due to 'internal' protection level

@MainActor func invalid() {
  _ = _Empty()
  _ = _Pair(first: Text("A"), next: Text("B"))
  _ = _Conditional<Text, Text>(content: .first(Text("A")))
  _ = _OptionalContent(content: Text("A"))
  _ = _Frame(content: Text("A"), style: .init())
  _ = _Background(content: Text("A"), color: .panel)
  _ = _Foreground(content: Text("A"), color: .text)
}
