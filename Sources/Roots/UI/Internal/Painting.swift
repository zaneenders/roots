extension UIStorage {
  mutating func emit(_ draw: DrawRect) {
    guard draw.isValid else { return }
    if let clip = draw.clip {
      guard clip.x.isFinite, clip.y.isFinite, clip.width.isFinite, clip.height.isFinite,
        !clip.intersection(draw.bounds).isEmpty
      else { return }
    }
    if let drawCapacity, draws.count >= drawCapacity {
      droppedDraws += 1
      return
    }
    draws.append(draw)
  }

  private mutating func paintScrollbar(at i: Int) {
    guard let bar = scrollbar(at: i) else { return }
    let node = nodes[i]
    let active = node.hovered || scrollbarDrag?.handle == handle(i)
    var painter = UIPaintContext(storage: &self, rect: node.rect, clip: node.clip, focused: false)
    bar.draw(into: &painter, active: active)
  }

  mutating func paint() {
    pendingScrollbars.removeAll()
    for position in 0..<order.count {
      let i = order[position]
      let node = nodes[i]
      while !pendingScrollbars.isEmpty,
        pendingScrollbars[pendingScrollbars.count - 1] != node.scrollParent
      {
        paintScrollbar(at: pendingScrollbars.removeLast())
      }
      if node.scrollable {
        pendingScrollbars.append(i)
        continue
      }
      var color = node.color
      let light = node.hover * 0.07 + node.flash * 0.12
      color.r += light
      color.g += light
      color.b += light
      emit(DrawRect(node.rect, color, radius: 7, clip: node.clip))
      let customPaint: ((inout UIPaintContext) -> Void)?
      switch node.interaction {
      case .element(_, _, _, let paint), .canvas(let paint): customPaint = paint
      default: customPaint = nil
      }
      if let paint = customPaint {
        let isFocused = focused == handle(i)
        var painter = UIPaintContext(
          storage: &self, rect: node.rect, clip: node.clip, focused: isFocused)
        paint(&painter)
      }
      if focused == handle(i), node.textLayout == nil {
        emit(
          DrawRect(
            Rect(
              node.rect.x + 1, node.rect.y + 1, max(0, node.rect.width - 2),
              max(0, node.rect.height - 2)),
            .accent, radius: 6, strokeWidth: 2, clip: node.clip))
      }
      if let layout = node.textLayout {
        paintText(layout, node: node, selected: focused == handle(i))
        continue
      }
      if customPaint != nil { continue }
      let textClip = node.clip.map { $0.intersection(node.rect) } ?? node.rect
      let font = node.font
      let y = node.rect.y + (node.rect.height - font.height(of: node.title)) / 2
      let title =
        node.textOverflow == .truncateTail
        ? font.truncating(node.title, to: node.rect.width - 24) : node.title
      drawText(title, x: node.rect.x + 12, y: y, font: font, color: .text, clip: textClip)
    }
    while !pendingScrollbars.isEmpty { paintScrollbar(at: pendingScrollbars.removeLast()) }
  }

  @discardableResult
  mutating func drawText(
    _ text: String, x: Float, y: Float, font: MonospaceFont, color: Color, clip: Rect?
  ) -> Float {
    let origin = x
    var x = x
    var y = y
    for character in text {
      if character == "\n" {
        x = origin
        y += font.lineHeight
        continue
      }
      let columns = MonospaceFont.columnWidth(of: character)
      drawGlyph(character, columns: columns, x: x, y: y, font: font, color: color, clip: clip)
      x += Float(columns) * font.advance
    }
    return x
  }

  private mutating func drawGlyph(
    _ character: Character, columns: Int, x: Float, y: Float, font: MonospaceFont, color: Color,
    clip: Rect?
  ) {
    let wide = columns == 2
    let rect = Rect(x, y, wide ? 2 * font.advance : font.glyphWidth, font.glyphHeight)
    guard x.isFinite, y.isFinite, character != " " else { return }
    if let clip, rect.intersection(clip).isEmpty { return }
    if wide {
      emit(
        DrawRect(
          rect, color, clip: clip, glyphUV: EmojiAtlas.shared.glyphUV(character), colorGlyph: true))
    } else {
      emit(DrawRect(rect, color, clip: clip, glyphUV: FontAtlas.shared.glyphUV(character)))
    }
  }
}
