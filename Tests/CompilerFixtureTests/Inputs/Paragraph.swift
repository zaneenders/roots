import Roots

@MainActor
func paragraph() -> some Block {
  Column(in: Region(0, 0, 200, 100)) {
    Paragraph {
      Text("Read ")
      Text("the docs")
        .color(.accent)
        .background(.panel)
      for value in [" now", "."] { Text(value) }
    }
    .size(14)
    .selectable(key: 1)
  }
}
