/// Immutable, owned pixels. Rows run top-to-bottom; RGBA uses straight alpha.
/// YUV formats are progressive 8-bit SDR with explicit chroma siting.
public final class ImageFrame: Sendable {
  public enum Format: Sendable { case rgba8, yuv420p, nv12 }
  public enum Matrix: Sendable { case bt601, bt709 }
  public enum ChromaLocation: Sendable { case center, left, topLeft }
  public enum Range: Sendable { case full, limited }
  public enum Error: Swift.Error { case invalidDimensions, invalidPlanes }

  public struct Plane: Sendable {
    public let bytes: [UInt8]
    public let bytesPerRow: Int

    public init(bytes: consuming [UInt8], bytesPerRow: Int) {
      self.bytes = bytes
      self.bytesPerRow = bytesPerRow
    }
  }

  public let width: Int
  public let height: Int
  public let format: Format
  public let planes: [Plane]
  /// (scaleX, scaleY, offsetX, offsetY) from luma UV to chroma UV.
  public let chromaTransform: SIMD4<Float>
  /// Rows of the affine YUV → RGB transform, applied to normalized (Y, U, V, 1).
  public let red: SIMD4<Float>
  public let green: SIMD4<Float>
  public let blue: SIMD4<Float>

  public init(
    width: Int, height: Int, format: Format, planes: consuming [Plane],
    matrix: Matrix = .bt709, range: Range = .limited, chromaLocation: ChromaLocation = .center
  ) throws {
    guard width > 0, height > 0, width <= 16_384, height <= 16_384 else {
      throw Error.invalidDimensions
    }
    let count = format == .rgba8 ? 1 : (format == .nv12 ? 2 : 3)
    guard planes.count == count else { throw Error.invalidPlanes }
    for (index, plane) in planes.enumerated() {
      let w = index == 0 ? width : (width + 1) / 2
      let h = index == 0 ? height : (height + 1) / 2
      let channels = format == .rgba8 ? 4 : (format == .nv12 && index == 1 ? 2 : 1)
      let (size, overflow) = plane.bytesPerRow.multipliedReportingOverflow(by: h)
      guard !overflow, plane.bytesPerRow >= w * channels,
        plane.bytesPerRow % channels == 0, plane.bytes.count >= size
      else { throw Error.invalidPlanes }
    }
    self.width = width
    self.height = height
    self.format = format
    self.planes = planes
    let cw = Float((width + 1) / 2)
    let ch = Float((height + 1) / 2)
    chromaTransform = SIMD4(
      Float(width) / (2 * cw), Float(height) / (2 * ch),
      chromaLocation == .center ? 0 : 0.25 / cw,
      chromaLocation == .topLeft ? 0.25 / ch : 0)
    let kr: Float = matrix == .bt709 ? 0.2126 : 0.299
    let kb: Float = matrix == .bt709 ? 0.0722 : 0.114
    let kg = 1 - kr - kb
    let y: Float = range == .limited ? 255 / 219 : 1
    let c: Float = range == .limited ? 255 / 224 : 1
    let black: Float = range == .limited ? 16 / 255 : 0
    let center: Float = 128 / 255
    func row(_ u: Float, _ v: Float) -> SIMD4<Float> {
      SIMD4(y, u * c, v * c, -y * black - (u + v) * c * center)
    }
    red = row(0, 2 * (1 - kr))
    green = row(-2 * kb * (1 - kb) / kg, -2 * kr * (1 - kr) / kg)
    blue = row(2 * (1 - kb), 0)
  }

  public func planeWidth(_ index: Int) -> Int { index == 0 ? width : (width + 1) / 2 }
  public func planeHeight(_ index: Int) -> Int { index == 0 ? height : (height + 1) / 2 }
  public func planeChannels(_ index: Int) -> Int {
    format == .rgba8 ? 4 : (format == .nv12 && index == 1 ? 2 : 1)
  }
}

/// A stable image identity whose pixels may change without rebuilding UI geometry.
/// Publish on MainActor; construct/decode immutable ImageFrames on a worker.
@MainActor
public final class ImageSource {
  public private(set) var frame: ImageFrame?
  private var observers: [UInt64: @MainActor () -> Void] = [:]
  private var nextObserver: UInt64 = 0

  public init(_ frame: ImageFrame? = nil) { self.frame = frame }

  public func publish(_ frame: ImageFrame?) {
    guard self.frame !== frame else { return }
    self.frame = frame
    for observer in Array(observers.values) { observer() }
  }

  package func observe(_ change: @escaping @MainActor () -> Void) -> UInt64 {
    precondition(nextObserver != UInt64.max)
    nextObserver += 1
    observers[nextObserver] = change
    return nextObserver
  }

  package func removeObserver(_ token: UInt64) { observers[token] = nil }
}
