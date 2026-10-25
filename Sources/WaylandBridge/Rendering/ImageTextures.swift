import CEGLGLES
import Roots

/// GL owns uploaded bytes after TexSubImage returns. Keep only the last CPU frame
/// for identity comparison; texture reuse is ordered by the owning GL context.
@safe @MainActor final class ImageTextures {
  private var names: [GLuint] = []
  private var frame: ImageFrame?

  func bind(_ next: ImageFrame) throws {
    let changed = frame !== next
    let allocate =
      frame?.width != next.width || frame?.height != next.height
      || frame?.format != next.format
    if allocate {
      close()
      names = [GLuint](repeating: 0, count: next.planes.count)
      unsafe glGenTextures(GLsizei(names.count), &names)
    }
    defer {
      glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 4)
      glPixelStorei(GLenum(GL_UNPACK_ROW_LENGTH), 0)
      glActiveTexture(GLenum(GL_TEXTURE0))
    }
    glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)
    for index in names.indices {
      glActiveTexture(GLenum(GL_TEXTURE2) + GLenum(index))
      glBindTexture(GLenum(GL_TEXTURE_2D), names[index])
      if allocate {
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
      }
      if changed {
        let channels = next.planeChannels(index)
        let format = channels == 4 ? GL_RGBA : (channels == 2 ? GL_RG : GL_RED)
        let internalFormat = channels == 4 ? GL_RGBA8 : (channels == 2 ? GL_RG8 : GL_R8)
        glPixelStorei(
          GLenum(GL_UNPACK_ROW_LENGTH), GLint(next.planes[index].bytesPerRow / channels))
        next.planes[index].bytes.withUnsafeBytes { bytes in
          if allocate {
            unsafe glTexImage2D(
              GLenum(GL_TEXTURE_2D), 0, internalFormat,
              GLsizei(next.planeWidth(index)), GLsizei(next.planeHeight(index)), 0,
              GLenum(format), GLenum(GL_UNSIGNED_BYTE), bytes.baseAddress)
          } else {
            unsafe glTexSubImage2D(
              GLenum(GL_TEXTURE_2D), 0, 0, 0,
              GLsizei(next.planeWidth(index)), GLsizei(next.planeHeight(index)),
              GLenum(format), GLenum(GL_UNSIGNED_BYTE), bytes.baseAddress)
          }
        }
      }
    }
    guard glGetError() == GL_NO_ERROR else { throw NativeWindowError.rendering }
    frame = next
  }

  func close() {
    if !names.isEmpty { unsafe glDeleteTextures(GLsizei(names.count), &names) }
    names.removeAll()
    frame = nil
  }
}
