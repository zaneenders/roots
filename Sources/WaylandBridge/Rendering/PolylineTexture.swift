import CEGLGLES
import Roots

/// One immutable upload per geometry. The renderer owns deletion on its GL context.
@safe @MainActor final class PolylineTexture {
  let stroke: PolylineStroke
  private var name: GLuint = 0

  init(_ stroke: PolylineStroke) throws {
    self.stroke = stroke
    // Three RGBA texels per point: position, color, and chunk bounds (first chunks.count rows).
    let count = stroke.points.count * 3
    let width = 256
    let height = (count + width - 1) / width
    var texels = [SIMD4<Float>](repeating: .zero, count: width * height)
    for index in stroke.points.indices {
      let point = stroke.points[index]
      let color = stroke.colors.isEmpty ? Color(1, 1, 1) : stroke.colors[index]
      texels[index * 3] = SIMD4(point.x, point.y, 0, 0)
      texels[index * 3 + 1] = SIMD4(color.r, color.g, color.b, color.a)
    }
    for (index, bounds) in stroke.chunks.enumerated() {
      texels[index * 3 + 2] = SIMD4(bounds.x, bounds.y, bounds.width, bounds.height)
    }
    unsafe glGenTextures(1, &name)
    glActiveTexture(GLenum(GL_TEXTURE5))
    glBindTexture(GLenum(GL_TEXTURE_2D), name)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_NEAREST)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_NEAREST)
    glPixelStorei(GLenum(GL_UNPACK_ROW_LENGTH), 0)
    texels.withUnsafeBytes { bytes in
      unsafe glTexImage2D(
        GLenum(GL_TEXTURE_2D), 0, GL_RGBA32F, GLsizei(width), GLsizei(height), 0,
        GLenum(GL_RGBA), GLenum(GL_FLOAT), bytes.baseAddress)
    }
    glActiveTexture(GLenum(GL_TEXTURE0))
    guard name != 0, glGetError() == GL_NO_ERROR else {
      close()
      throw NativeWindowError.rendering
    }
  }

  func bind() {
    glActiveTexture(GLenum(GL_TEXTURE5))
    glBindTexture(GLenum(GL_TEXTURE_2D), name)
    glActiveTexture(GLenum(GL_TEXTURE0))
  }

  func close() {
    if name != 0 {
      unsafe glDeleteTextures(1, &name)
      name = 0
    }
  }
}
