import Roots

private struct Item {
  let id: String
  let title: String
}

@MainActor
func automaticSelection() -> some Block {
  Column(in: Region(0, 0, 200, 200)) {
    Text("Heading")
      .selectable()
    ForEach([Item(id: "a", title: "First")], id: \.id) { item in
      Text(item.title)
        .selectable()
      Paragraph { Text(item.title) }
        .selectable()
    }
  }
}
