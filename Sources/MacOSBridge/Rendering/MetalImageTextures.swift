import Metal
import Roots

/// Each submission slot has its own textures; never replace bytes while that
/// slot's command buffer is reading them.
@safe @MainActor final class MetalImageTextures {
  private(set) var textures: [any MTLTexture] = []
  private var frame: ImageFrame?

  func update(_ next: ImageFrame, device: any MTLDevice) throws {
    guard frame !== next else { return }
    if frame?.width != next.width || frame?.height != next.height || frame?.format != next.format {
      textures.removeAll()
      for index in next.planes.indices {
        let channels = next.planeChannels(index)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
          pixelFormat: channels == 4 ? .rgba8Unorm : (channels == 2 ? .rg8Unorm : .r8Unorm),
          width: next.planeWidth(index), height: next.planeHeight(index), mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
          throw MacOSWindowError.resourceAllocation
        }
        textures.append(texture)
      }
    }
    for index in textures.indices {
      next.planes[index].bytes.withUnsafeBytes { bytes in
        unsafe textures[index].replace(
          region: MTLRegionMake2D(0, 0, next.planeWidth(index), next.planeHeight(index)),
          mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: next.planes[index].bytesPerRow
        )
      }
    }
    frame = next
  }
}
