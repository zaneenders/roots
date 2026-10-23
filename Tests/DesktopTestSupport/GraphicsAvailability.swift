#if os(macOS)
import CoreGraphics
import Metal
#endif

@MainActor public enum GraphicsAvailability {
  #if os(Linux)
  public static var offscreen: Bool { EGLAvailability.isAvailable }
  #elseif os(macOS)
  public static let offscreen = MTLCreateSystemDefaultDevice() != nil
  public static let window = offscreen && CGSessionCopyCurrentDictionary() != nil
  #elseif os(Windows)
  public static let offscreen = true
  #endif
}
