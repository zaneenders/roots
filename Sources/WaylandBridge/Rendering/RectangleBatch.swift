import Roots

struct RectangleBatch: ~Copyable {
  static let capacity = 1024
  static let vertexFloats = 17
  private(set) var storage = UniqueArray<Float>(repeating: 0, count: capacity * vertexFloats)
  private(set) var count = 0

  var vertices: Span<Float> {
    @_lifetime(borrow self)
    borrowing get { storage.span.extracting(first: count * Self.vertexFloats) }
  }

  static func accepts(_ draw: DrawRect) -> Bool { draw.isValid }

  mutating func append(_ draw: DrawRect) {
    precondition(count < Self.capacity && draw.polyline == nil)
    let offset = count * Self.vertexFloats
    var vertices = storage.mutableSpan
    vertices[offset] = draw.rect.x
    vertices[offset + 1] = draw.rect.y
    vertices[offset + 2] = draw.rect.width
    vertices[offset + 3] = draw.rect.height
    vertices[offset + 4] = draw.color.r
    vertices[offset + 5] = draw.color.g
    vertices[offset + 6] = draw.color.b
    vertices[offset + 7] = draw.color.a
    vertices[offset + 8] = draw.radius
    vertices[offset + 9] = draw.glyphUV?.x ?? 0
    vertices[offset + 10] = draw.glyphUV?.y ?? 0
    vertices[offset + 11] = draw.glyphUV?.width ?? 0
    vertices[offset + 12] = draw.glyphUV?.height ?? 0
    vertices[offset + 13] = draw.glyphUV == nil ? 0 : (draw.colorGlyph ? 2 : 1)
    vertices[offset + 14] = draw.strokeWidth
    vertices[offset + 15] = draw.axis.x
    vertices[offset + 16] = draw.axis.y
    count += 1
  }

  mutating func reset() { count = 0 }
}
