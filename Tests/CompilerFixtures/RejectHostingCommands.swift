import Roots

@MainActor func invalid() {
  _ = Focus(key: 1)
  _ = ScrollTo(10, in: 1)
}
