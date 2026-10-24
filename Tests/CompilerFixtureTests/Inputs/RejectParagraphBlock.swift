import Roots
// expected-error: no exact matches in call to static method 'buildExpression'

@MainActor
func invalid() {
  _ = Paragraph { Button(key: 1, "not inline text") }
}
