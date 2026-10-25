import CEGLGLES
import Roots

@safe @MainActor final class RibbonBuffer {
  let stroke: PolylineStroke
  let count: GLsizei
  private var buffer: GLuint = 0
  private var array: GLuint = 0

  init(_ stroke: PolylineStroke, ribbon: StrokeRibbon) throws {
    self.stroke = stroke
    count = GLsizei(ribbon.vertices.count)
    unsafe glGenBuffers(1, &buffer)
    unsafe glGenVertexArrays(1, &array)
    glBindVertexArray(array)
    glBindBuffer(GLenum(GL_ARRAY_BUFFER), buffer)
    ribbon.vertices.withUnsafeBytes { bytes in
      unsafe glBufferData(GLenum(GL_ARRAY_BUFFER), bytes.count, bytes.baseAddress, GLenum(GL_STATIC_DRAW))
    }
    let offsets = [
      MemoryLayout<StrokeRibbon.Vertex>.offset(of: \.geometry)!,
      MemoryLayout<StrokeRibbon.Vertex>.offset(of: \.color)!, MemoryLayout<StrokeRibbon.Vertex>.offset(of: \.edge)!
    ]
    for index in 0..<3 {
      glEnableVertexAttribArray(GLuint(index))
      unsafe glVertexAttribPointer(
        GLuint(index), 4, GLenum(GL_FLOAT), GLboolean(GL_FALSE),
        GLsizei(MemoryLayout<StrokeRibbon.Vertex>.stride), UnsafeRawPointer(bitPattern: offsets[index]))
    }
    glBindVertexArray(0)
    guard glGetError() == GL_NO_ERROR else {
      close()
      throw NativeWindowError.rendering
    }
  }

  func draw() {
    glBindVertexArray(array)
    glDrawArrays(GLenum(GL_TRIANGLES), 0, count)
    glBindVertexArray(0)
  }

  func close() {
    if array != 0 {
      unsafe glDeleteVertexArrays(1, &array)
      array = 0
    }
    if buffer != 0 {
      unsafe glDeleteBuffers(1, &buffer)
      buffer = 0
    }
  }
}
