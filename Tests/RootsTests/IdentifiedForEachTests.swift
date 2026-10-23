import Testing

@_spi(Hosting) @testable import Roots

@MainActor
struct IdentifiedForEachTests {
  struct Item {
    let id: String
    let title: String
  }

  @Test func selectionFollowsItemIdentityAcrossReorderingAndInsertion() {
    var host = UIHost()
    var items = [Item(id: "a", title: "Alpha"), Item(id: "b", title: "Beta")]
    func render(_ input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          Column(in: Region(0, 0, 200, 200), gap: 0) {
            ForEach(items, id: \.id) { item in
              Text(item.title)
                .size(10)
                .selectable()
            }
          }
        }, present: { _ in })
    }
    render(Input(x: 0, y: 19, pressed: true))
    render(Input(x: 24, y: 19, released: true))
    #expect(host.selectedText == "Beta")
    items = [items[1], Item(id: "c", title: "Gamma"), items[0]]
    render()
    #expect(host.selectedText == "Beta")
    items.removeFirst()
    render()
    #expect(host.selectedText == nil)
    #expect(host.liveCount == 2)
  }

  @Test func childCallSitesDoNotShiftWhenAConditionalSiblingAppears() {
    var host = UIHost()
    var showDetail = false
    func render(_ input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          Column(in: Region(0, 0, 200, 200), gap: 0) {
            ForEach(["item"], id: \.self) { item in
              if showDetail {
                Text("Detail")
                  .size(10)
                  .selectable()
              }
              Text(item)
                .size(10)
                .selectable()
            }
          }
        }, present: { _ in })
    }
    render(Input(x: 0, y: 5, pressed: true))
    render(Input(x: 24, y: 5, released: true))
    #expect(host.selectedText == "item")
    showDetail = true
    render()
    #expect(host.selectedText == "item")
  }

  @Test func differentCollectionsAndNestedItemsHaveSeparateIdentity() {
    var host = UIHost()
    var parents = ["first", "second"]
    func render(_ input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          Column(in: Region(0, 0, 200, 200), gap: 0) {
            ForEach(["same"], id: \.self) { item in
              Text(item).size(10).selectable()
            }
            ForEach(parents, id: \.self) { parent in
              ForEach(["same"], id: \.self) { _ in
                Paragraph { Text(parent) }
                  .size(10)
                  .selectable()
              }
            }
          }
        }, present: { _ in })
    }
    render(Input(x: 0, y: 33, pressed: true))
    render(Input(x: 36, y: 33, released: true))
    #expect(host.selectedText == "second")
    parents.reverse()
    render()
    #expect(host.selectedText == "second")
    #expect(host.liveCount == 3)
  }

  @Test func implicitKeysCannotCollideWithExplicitNumericKeys() {
    var host = UIHost()
    host.frame(
      build: {
        Column(in: Region(0, 0, 200, 200)) {
          Text("Explicit").selectable(key: 0)
          ForEach([0, 1], id: \.self) { item in
            Text("Item \(item)").selectable()
          }
        }
      }, present: { _ in })
    #expect(host.liveCount == 3)
    #expect(host.state(for: 0) != nil)
    #expect(host.state(for: 1) == nil)
  }

  @Test func implicitSelectionParticipatesInDocumentSelection() {
    var host = UIHost()
    func render(_ input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          Column(in: Region(0, 0, 200, 200), gap: 0) {
            ForEach(["first", "second"], id: \.self) { item in
              Text(item).size(10).selectable()
            }
          }.selectionGroup(key: 100)
        }, present: { _ in })
    }
    render(Input(x: 0, y: 5, pressed: true, released: true))
    render(Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]))
    #expect(host.selectedText == "first\nsecond")
  }

  @Test func duplicateItemIDsAreRejected() async {
    await #expect(processExitsWith: .failure) {
      await MainActor.run {
        var host = UIHost()
        host.frame(
          build: {
            Column(in: Region(0, 0, 200, 200)) {
              ForEach([1, 1], id: \.self) { value in Text("\(value)").selectable() }
            }
          }, present: { _ in })
      }
    }
  }
  @Test func staticSelectionCallSitesKeepTheirStateAcrossFrames() {
    var host = UIHost()
    func render(_ input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          Column(in: Region(0, 0, 100, 100), gap: 0) {
            Text("first").size(10).selectable()
            Text("second").size(10).selectable()
          }
        }, present: { _ in })
    }
    render(Input(x: 0, y: 5, pressed: true))
    render(Input(x: 30, y: 5, released: true))
    #expect(host.selectedText == "first")
    render()
    #expect(host.selectedText == "first")
    #expect(host.liveCount == 2)
  }

  @Test func explicitSelectionKeysRemainAnEscapeHatchWithinIdentifiedItems() {
    var host = UIHost()
    host.frame(
      input: Input(keyEvents: [KeyEvent(.character("a"), modifiers: .control)]),
      build: {
        Column(in: Region(0, 0, 100, 100)) {
          ForEach(["first"], id: \.self) { item in
            Text(item)
              .selectable()
              .selectable(key: 42)
          }
        }
        FocusBlock(key: 42)
      }, present: { _ in })
    #expect(host.state(for: 42)?.focused == true)
    #expect(host.selectedText == "first")
  }

  @Test func removedItemDoesNotRecoverOldSelectionWhenReinserted() {
    var host = UIHost()
    var items = ["value"]
    func render(_ input: Input = Input()) {
      host.frame(
        input: input,
        build: {
          Column(in: Region(0, 0, 100, 100)) {
            ForEach(items, id: \.self) { item in
              Text(item).size(10).selectable()
            }
          }
        }, present: { _ in })
    }
    render(Input(x: 0, y: 5, pressed: true))
    render(Input(x: 30, y: 5, released: true))
    #expect(host.selectedText == "value")
    items = []
    render()
    #expect(host.liveCount == 0)
    items = ["value"]
    render()
    #expect(host.liveCount == 1)
    #expect(host.selectedText == nil)
  }

}
