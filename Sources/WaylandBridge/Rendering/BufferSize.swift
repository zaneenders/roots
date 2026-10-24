struct BufferSize: Equatable {
  let width: Int32
  let height: Int32

  init(width: Int32, height: Int32, scale: Int32 = 1, fractionalScale120: UInt32? = nil) throws {
    guard width > 0, height > 0, scale > 0, fractionalScale120 != 0 else {
      throw NativeWindowError.invalidConfiguration
    }
    // Keep the protocol's 1/120 ratio exact, including halfway rounding.
    func pixels(_ size: Int32) -> Int64 {
      if let fractionalScale120 { return (Int64(size) * Int64(fractionalScale120) + 60) / 120 }
      return Int64(size) * Int64(scale)
    }
    let pixelWidth = pixels(width)
    let pixelHeight = pixels(height)
    guard pixelWidth > 0, pixelHeight > 0,
      pixelWidth <= Int32.max, pixelHeight <= Int32.max
    else { throw NativeWindowError.invalidConfiguration }
    self.width = Int32(pixelWidth)
    self.height = Int32(pixelHeight)
  }
}
