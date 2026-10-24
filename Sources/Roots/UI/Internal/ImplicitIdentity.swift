@usableFromInline
struct IdentityLocation: Hashable {
  let file: String
  let line: UInt
  let column: UInt

  @usableFromInline
  init(file: StaticString, line: UInt, column: UInt) {
    self.file = String(describing: file)
    self.line = line
    self.column = column
  }
}

struct ItemIdentity: Hashable {
  let location: IdentityLocation
  let value: AnyHashable
}

struct ImplicitNodeIdentity: Hashable {
  let path: [ItemIdentity]
  let location: IdentityLocation
}
