import CVideoDecoder
import Dispatch
import Foundation
import Roots

struct DecodedFrame: Sendable {
  let image: ImageFrame
  let seconds: Double
}

struct DecodeError: Error, CustomStringConvertible {
  let description: String
}

/// FFmpeg's blocking calls run on a dedicated serial queue, never MainActor or
/// the cooperative executor. Only immutable Swift-owned frames cross actors.
private final class DecoderExecutor: SerialExecutor {
  private let queue = DispatchQueue(label: "roots.example.video.decode")
  func enqueue(_ job: consuming ExecutorJob) {
    let job = UnownedJob(job)
    queue.async { unsafe job.runSynchronously(on: self.asUnownedSerialExecutor()) }
  }
}

@safe actor Decoder {
  private nonisolated let executor = DecoderExecutor()
  nonisolated var unownedExecutor: UnownedSerialExecutor {
    unsafe executor.asUnownedSerialExecutor()
  }
  private var handle: OpaquePointer?

  func open(_ path: String) throws {
    close()
    var message = [CChar](repeating: 0, count: 512)
    unsafe handle = roots_video_open(path, &message, Int32(message.count))
    guard unsafe handle != nil else { throw error(message) }
  }

  func next() throws -> DecodedFrame? {
    guard let handle = unsafe handle else { throw DecodeError(description: "Decoder is closed") }
    var message = [CChar](repeating: 0, count: 512)
    let result = unsafe roots_video_next(handle, &message, Int32(message.count))
    guard result >= 0 else { throw error(message) }
    guard result > 0 else { return nil }
    let width = Int(unsafe roots_video_width(handle))
    let height = Int(unsafe roots_video_height(handle))
    var planes: [ImageFrame.Plane] = []
    for index in 0..<3 {
      let rows = index == 0 ? height : (height + 1) / 2
      let stride = Int(unsafe roots_video_stride(handle, Int32(index)))
      let columns = index == 0 ? width : (width + 1) / 2
      guard let address = unsafe roots_video_plane(handle, Int32(index)), abs(stride) >= columns
      else {
        throw DecodeError(description: "Invalid decoded plane")
      }
      var bytes = [UInt8]()
      bytes.reserveCapacity(columns * rows)
      for row in 0..<rows {
        unsafe bytes.append(
          contentsOf: UnsafeBufferPointer(start: address.advanced(by: row * stride), count: columns)
        )
      }
      planes.append(.init(bytes: bytes, bytesPerRow: columns))
    }
    return try DecodedFrame(
      image: ImageFrame(
        width: width, height: height, format: .yuv420p, planes: planes,
        matrix: unsafe roots_video_bt709(handle) != 0 ? .bt709 : .bt601,
        range: unsafe roots_video_full_range(handle) != 0 ? .full : .limited,
        chromaLocation: unsafe roots_video_chroma(handle) == 0
          ? .center
          : (roots_video_chroma(handle) == 1 ? .left : .topLeft)),
      seconds: unsafe roots_video_time(handle))
  }

  func close() {
    unsafe roots_video_close(handle)
    unsafe handle = nil
  }

  isolated deinit { unsafe roots_video_close(handle) }

  private func error(_ message: [CChar]) -> DecodeError {
    DecodeError(
      description: String(
        decoding: message.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
  }
}
