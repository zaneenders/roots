import Roots

@MainActor
func document() -> some Block {
  SelectionGroup(key: 100) {
    Column(in: Region(0, 0, 100, 200)) {
      Text("Heading")
        .selectable(key: 1)
      Paragraph {
        Text("Body")
      }
      .selectable(key: 2)
    }
  }
}
