import Roots

@MainActor @BlockBuilder func invalid() -> some Block {
  print("not a declaration")
}
