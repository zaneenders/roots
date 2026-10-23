import Roots
import RootsDesktop

struct MarkdownPage: Block {
  let bounds: Region
  var copyCode: (String) -> Void = { text in
    _ = DesktopSystem.writeClipboard(text)
  }

  var body: some Block {
    ZStack(in: bounds) {
      ScrollColumn(key: 1, in: bounds, gap: 0, showsScrollIndicator: true) {
        Column(gap: 22) {
          Text("ROOTS / TEXT PLAYGROUND")
            .size(12)
            .color(Ink.muted)
            .selectable(key: 30)

          Paragraph {
            Text("A small document, ")
            Text("made of text.")
              .color(Ink.accent)
          }
          .size(32)
          .selectable(key: 2)

          Paragraph {
            Text("This page is composed with ")
            Text("Paragraph")
              .color(Ink.accent)
              .background(Ink.code)
            Text(" and ordinary Text children. Resize the window to watch the words reflow, ")
            Text("without losing their style")
              .color(Ink.gold)
            Text(". Select across colors and lines, then copy: visual wraps are not inserted into the clipboard text.")
          }
          .size(16)
          .selectable(key: 3)

          Text("01 / Inline styling")
            .size(21)
            .color(Ink.heading)
            .selectable(key: 31)

          Paragraph {
            Text("A paragraph can mix ")
            Text("accent colors")
              .color(Ink.accent)
            Text(", ")
            Text("inline code")
              .color(Ink.gold)
              .background(Ink.code)
            Text(", and ")
            Text("larger text")
              .size(24)
              .color(Ink.rose)
            Text(" on one baseline. Unicode stays intact too: café, e\u{301}, and 👩‍💻. ")
            Text("Link-looking text")
              .color(Ink.accent)
            Text(" is only styled here; this demo does not install a link handler.")
          }
          .size(16)
          .selectable(key: 4)

          Paragraph {
            Text("“Layout should follow the words, not the other way around.”")
          }
          .size(19)
          .color(Ink.heading)
          .selectable(key: 5)
          .padding(18)
          .frame(width: .fill)
          .background(Ink.panel)

          Text("02 / A short list")
            .size(21)
            .color(Ink.heading)
            .selectable(key: 32)

          Column(gap: 10) {
            ForEach(Self.list, id: \.self) { item in
              Paragraph {
                Text("• ")
                  .color(Ink.accent)
                Text(item)
              }
              .size(16)
              .selectable()
            }
          }
          .frame(width: .fill)

          Text("03 / Code, without Markdown parsing")
            .size(21)
            .color(Ink.heading)
            .selectable(key: 33)

          Column(gap: 14) {
            RowBlock(gap: 12, alignment: .center) {
              Text("SWIFT")
                .size(12)
                .color(Ink.muted)
                .selectable(key: 34)
                .frame(width: .fill, alignment: .leading)
              Button(key: 35, "Copy code", extent: 108, color: Ink.panel, size: 12) {
                copyCode(Self.code)
              }
            }
            .frame(width: .fill, height: .fixed(32))
            Text(Self.code)
              .size(14)
              .color(Ink.gold)
              .selectable(key: 20)
          }
          .padding(18)
          .frame(width: .fill)
          .background(Ink.code)

          Paragraph {
            Text("What you are seeing: ")
              .color(Ink.heading)
            Text("headings, paragraphs, a quote, a list, and a literal code sample. ")
            Text("Not a Markdown parser")
              .color(Ink.rose)
            Text(". Bold, italic, and automatic code wrapping are not implemented here.")
          }
          .size(14)
          .color(Ink.muted)
          .selectable(key: 21)
        }
        .padding(32)
        .frame(width: .fill)
        .selectionGroup(key: 100)
      }
    }
    .background(Ink.page)
    .color(Ink.body)
  }

  static let list = [
    "Each Paragraph is a single selectable text flow, even when its children use different colors.",
    "Padding and backgrounds belong to the container; text only describes the content.",
    "The renderer computes line breaks and paragraph height from the available width."
  ]

  static let code = """
    Paragraph {
      Text("Hello ")
      Text("world")
        .color(.accent)
    }
    .size(16)
    .selectable(key: 42)
    """
}

enum Ink {
  static let page = Color(0.035, 0.05, 0.08)
  static let panel = Color(0.08, 0.12, 0.18)
  static let code = Color(0.055, 0.075, 0.12)
  static let body = Color(0.77, 0.83, 0.90)
  static let heading = Color(0.95, 0.96, 0.98)
  static let muted = Color(0.47, 0.57, 0.69)
  static let accent = Color(0.32, 0.84, 0.77)
  static let gold = Color(0.98, 0.78, 0.43)
  static let rose = Color(0.95, 0.56, 0.64)
}
