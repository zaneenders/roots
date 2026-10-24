import Roots
// expected-error: type '()' cannot conform to 'Block'

@MainActor @BlockBuilder func invalid() -> some Block {
  print("not a declaration")
}
