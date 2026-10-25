public enum DrawCommand: Sendable {
  case rectangle(DrawRect)
  case image(ImageDraw)
}

public enum ImageContentMode: Sendable { case fit, fill, stretch }

public struct ImageDraw: Sendable {
  public let source: ImageSource
  public let region: Region
  public let clip: Region?
  public let opacity: Float
  public let contentMode: ImageContentMode

  public init(
    _ source: ImageSource, in region: Region, clip: Region? = nil,
    opacity: Float = 1, contentMode: ImageContentMode = .fit
  ) {
    self.source = source
    self.region = region
    self.clip = clip
    self.opacity = opacity
    self.contentMode = contentMode
  }

  public var isValid: Bool {
    guard opacity.isFinite, opacity > 0,
      region.x.isFinite, region.y.isFinite, region.width.isFinite, region.height.isFinite,
      !region.isEmpty, (region.x + region.width).isFinite, (region.y + region.height).isFinite
    else { return false }
    if let clip {
      guard clip.x.isFinite, clip.y.isFinite, clip.width.isFinite, clip.height.isFinite,
        !clip.intersection(region).isEmpty
      else { return false }
    }
    return true
  }

  /// Resolve once per submission. The returned value owns the selected CPU frame.
  @MainActor public func resolve() -> ResolvedImageDraw? {
    guard isValid, let frame = source.frame else { return nil }
    var destination = region
    var uv = Region(0, 0, 1, 1)
    let x = region.width / Float(frame.width)
    let y = region.height / Float(frame.height)
    guard x > 0, y > 0 else { return nil }
    switch contentMode {
    case .fit:
      let scale = min(x, y)
      destination.width = Float(frame.width) * scale
      destination.height = Float(frame.height) * scale
      destination.x += (region.width - destination.width) / 2
      destination.y += (region.height - destination.height) / 2
    case .fill:
      let scale = max(x, y)
      uv.width = x / scale
      uv.height = y / scale
      uv.x = (1 - uv.width) / 2
      uv.y = (1 - uv.height) / 2
    case .stretch: break
    }
    return ResolvedImageDraw(
      source: source, frame: frame, region: destination, uv: uv,
      clip: clip, opacity: min(1, opacity))
  }
}

public struct ResolvedImageDraw: Sendable {
  public let source: ImageSource
  public let frame: ImageFrame
  public let region: Region
  public let uv: Region
  public let clip: Region?
  public let opacity: Float

  package var rectangle: DrawRect {
    DrawRect(region, Color(1, 1, 1, opacity), clip: clip, glyphUV: uv)
  }
}
