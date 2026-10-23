import Roots

@MainActor
func invalid() {
  _ = Paragraph { Button(key: 1, "not inline text") }
}
