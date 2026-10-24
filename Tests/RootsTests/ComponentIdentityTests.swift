import Testing

@_spi(Hosting) @testable import Roots

@MainActor
struct ComponentIdentityTests {
  struct Selectable: Block {
    let value: String
    var paragraph = false
    var body: some Block {
      if paragraph {
        Paragraph { Text(value) }.size(10).selectable()
      } else {
        Text(value).size(10).selectable()
      }
    }
  }

  @Test(arguments: [false, true])
  func siblingComponentsKeepIndependentSelection(paragraph: Bool) {
    var host = UIHost()
    func render(_ input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          Column(in: Region(0, 0, 200, 200), gap: 0) {
            Selectable(value: "First", paragraph: paragraph)
            Selectable(value: "Second", paragraph: paragraph)
          }
        }, present: { _ in })
    }
    render(Input(mousePosition: .init(x: 0, y: 19), pressed: true))
    render(Input(mousePosition: .init(x: 36, y: 19), released: true))
    #expect(host.selectedText == "Second")
    render()
    #expect(host.selectedText == "Second")
    render(Input(mousePosition: .init(x: 0, y: 5), pressed: true))
    render(Input(mousePosition: .init(x: 30, y: 5), released: true))
    #expect(host.selectedText == "First")
    #expect(host.liveCount == 2)
  }

  struct List: Block {
    let items: [String]
    var body: some Block {
      ForEach(items, id: \.self) { Selectable(value: $0) }
    }
  }

  @Test func repeatedListsScopeItemIDsAndPreserveSelectionThroughReordering() {
    var host = UIHost()
    var items = ["Alpha", "Beta"]
    func render(_ input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          Column(in: Region(0, 0, 200, 200), gap: 0) {
            List(items: ["Alpha"])
            List(items: items)
          }
        }, present: { _ in })
    }
    render(Input(mousePosition: .init(x: 0, y: 33), pressed: true))
    render(Input(mousePosition: .init(x: 24, y: 33), released: true))
    #expect(host.selectedText == "Beta")
    items.reverse()
    render()
    #expect(host.selectedText == "Beta")
    items.removeFirst()
    render()
    #expect(host.selectedText == nil)
    #expect(host.liveCount == 2)
  }

  @Test func conditionalSiblingDoesNotChangeComponentIdentity() {
    var host = UIHost()
    var showDetail = false
    func render(_ input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          Column(in: Region(0, 0, 200, 200), gap: 0) {
            if showDetail { Selectable(value: "Detail") }
            Selectable(value: "Value")
          }
        }, present: { _ in })
    }
    render(Input(mousePosition: .init(x: 0, y: 5), pressed: true))
    render(Input(mousePosition: .init(x: 30, y: 5), released: true))
    #expect(host.selectedText == "Value")
    showDetail = true
    render()
    #expect(host.selectedText == "Value")
    #expect(host.liveCount == 2)
  }

  @Test func switchingBranchesDoesNotTransferSelection() {
    var host = UIHost()
    var first = true
    func render(_ input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          Column(in: Region(0, 0, 200, 200)) {
            if first { Selectable(value: "Same") } else { Selectable(value: "Same") }
          }
        }, present: { _ in })
    }
    render(Input(mousePosition: .init(x: 0, y: 5), pressed: true))
    render(Input(mousePosition: .init(x: 24, y: 5), released: true))
    #expect(host.selectedText == "Same")
    first = false
    render()
    #expect(host.selectedText == nil)
  }
}
