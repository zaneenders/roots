struct BufferSize: Equatable {
  let width: Int32
  let height: Int32

  init(width: Int32, height: Int32, scale: Int32) throws {
    let (pixelWidth, widthOverflow) = width.multipliedReportingOverflow(by: scale)
    let (pixelHeight, heightOverflow) = height.multipliedReportingOverflow(by: scale)
    guard width > 0, height > 0, scale > 0, !widthOverflow, !heightOverflow else {
      throw NativeWindowError.invalidConfiguration
    }
    self.width = pixelWidth
    self.height = pixelHeight
  }
}
