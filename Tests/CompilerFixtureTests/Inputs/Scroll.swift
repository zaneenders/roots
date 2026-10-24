import Roots

@MainActor
func scrollingLayouts(in bounds: Region) -> some Block {
  Stack(in: bounds) {
    Scroll(key: 1, in: bounds) {
      Row {
        Text("First")
        Text("Second")
      }
    }
    Scroll(key: 2, in: bounds, showsScrollIndicator: true) {
      Grid(columns: 2) {
        ForEach(0..<4) { _ in Rectangle().frame(height: .fixed(40)) }
      }
    }
  }
}
