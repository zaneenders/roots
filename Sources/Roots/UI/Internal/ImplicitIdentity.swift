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

@usableFromInline
enum IdentityComponent: Hashable {
  case child(Int)
  case item(IdentityLocation, AnyHashable)
}

struct ImplicitNodeIdentity: Hashable {
  let path: [IdentityComponent]
  let location: IdentityLocation
}
