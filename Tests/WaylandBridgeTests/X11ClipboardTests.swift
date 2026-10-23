import Foundation
import Testing

@testable import WaylandBridge

@Test func x11ClipboardReadsShortEmptyUnicodeAndMultilineText() {
  for text in ["", "hello", "café 🙂\n第二行\n"] {
    var buffer = X11ClipboardReadBuffer()
    #expect(buffer.receive(Array(text.utf8), format: 8, bytesAfter: 0) == .complete(text))
    #expect(buffer.finished)
    #expect(buffer.receive([], format: 8, bytesAfter: 0) == .invalid)
  }
}

@Test func x11ClipboardAssemblesRegularPropertyFragments() {
  var buffer = X11ClipboardReadBuffer()
  #expect(buffer.receive(Array("abcd".utf8), format: 8, bytesAfter: 7) == .moreProperty(offset: 1))
  #expect(buffer.receive(Array("efgh".utf8), format: 8, bytesAfter: 3) == .moreProperty(offset: 2))
  #expect(buffer.receive(Array("ijk".utf8), format: 8, bytesAfter: 0) == .complete("abcdefghijk"))
}

@Test func x11ClipboardINCRSupportsSplitCodePointsAndEmptyFinalChunks() {
  let text = "🙂café\n"
  let bytes = Array(text.utf8)
  var buffer = X11ClipboardReadBuffer()
  #expect(
    buffer.beginIncremental(
      advertisedBytes: UInt32(bytes.count), format: 32, valueCount: 1, bytesAfter: 0) == true)
  #expect(buffer.receive(Array(bytes.prefix(2)), format: 8, bytesAfter: 0) == .nextChunk)
  #expect(buffer.receive(Array(bytes.dropFirst(2)), format: 8, bytesAfter: 0) == .nextChunk)
  #expect(buffer.receive([], format: 8, bytesAfter: 0) == .complete(text))
  #expect(buffer.finished)
}

@Test func x11ClipboardINCRAssemblesFragmentedPropertiesWithoutPrematureTermination() {
  var buffer = X11ClipboardReadBuffer()
  #expect(
    buffer.beginIncremental(advertisedBytes: 0, format: 32, valueCount: 1, bytesAfter: 0) == true)
  #expect(buffer.receive(Array("abcd".utf8), format: 8, bytesAfter: 2) == .moreProperty(offset: 1))
  #expect(buffer.receive(Array("ef".utf8), format: 8, bytesAfter: 0) == .nextChunk)
  // The offset is relative to each property, not the complete INCR transfer.
  #expect(buffer.receive(Array("ghij".utf8), format: 8, bytesAfter: 2) == .moreProperty(offset: 1))
  #expect(buffer.receive(Array("kl".utf8), format: 8, bytesAfter: 0) == .nextChunk)
  #expect(buffer.receive([], format: 8, bytesAfter: 0) == .complete("abcdefghijkl"))
}

@Test func x11ClipboardAllowsAnEmptyINCRTransfer() {
  var buffer = X11ClipboardReadBuffer()
  #expect(
    buffer.beginIncremental(advertisedBytes: 0, format: 32, valueCount: 1, bytesAfter: 0) == true)
  #expect(buffer.receive([], format: 8, bytesAfter: 0) == .complete(""))
}

@Test func x11ClipboardRejectsMalformedINCRAnnouncements() {
  for (size, format, count, after): (UInt32, UInt8, Int, UInt32) in [
    (0, 8, 1, 0), (0, 16, 1, 0), (0, 32, 0, 0), (0, 32, 2, 0), (0, 32, 1, 4),
    (UInt32(X11ClipboardLimits.maximumBytes + 1), 32, 1, 0), (UInt32.max, 32, 1, 0),
  ] {
    var buffer = X11ClipboardReadBuffer()
    #expect(
      buffer.beginIncremental(
        advertisedBytes: size, format: format, valueCount: count, bytesAfter: after) == false)
    #expect(buffer.finished)
  }
  var twice = X11ClipboardReadBuffer()
  #expect(
    twice.beginIncremental(advertisedBytes: 0, format: 32, valueCount: 1, bytesAfter: 0) == true)
  #expect(
    twice.beginIncremental(advertisedBytes: 0, format: 32, valueCount: 1, bytesAfter: 0) == false)
}

@Test func x11ClipboardRejectsTruncationInvalidUTF8AndPropertyFormats() {
  var truncated = X11ClipboardReadBuffer()
  #expect(
    truncated.beginIncremental(advertisedBytes: 3, format: 32, valueCount: 1, bytesAfter: 0) == true
  )
  #expect(truncated.receive([65, 66], format: 8, bytesAfter: 0) == .nextChunk)
  #expect(truncated.receive([], format: 8, bytesAfter: 0) == .invalid)
  for invalid in [[UInt8(0xff)], [0xf0, 0x9f], [0xc0, 0x80]] {
    var buffer = X11ClipboardReadBuffer()
    #expect(buffer.receive(invalid, format: 8, bytesAfter: 0) == .invalid)
  }
  for format: UInt8 in [0, 16, 32] {
    var buffer = X11ClipboardReadBuffer()
    #expect(buffer.receive([], format: format, bytesAfter: 0) == .invalid)
  }
}

@Test func x11ClipboardRejectsOversizedPropertiesBeforeAllocatingTheirRemainder() {
  for after in [UInt32(X11ClipboardLimits.maximumBytes), UInt32.max] {
    var buffer = X11ClipboardReadBuffer()
    #expect(buffer.receive([65, 65, 65, 65], format: 8, bytesAfter: after) == .invalid)
  }
  var stalled = X11ClipboardReadBuffer()
  #expect(stalled.receive([], format: 8, bytesAfter: 4) == .invalid)
  var misaligned = X11ClipboardReadBuffer()
  #expect(misaligned.receive([65], format: 8, bytesAfter: 4) == .invalid)
}

@Test func x11ClipboardCapAppliesAcrossEveryINCRChunk() {
  let chunk = [UInt8](repeating: 65, count: X11ClipboardLimits.chunkBytes)
  var exact = X11ClipboardReadBuffer()
  #expect(
    exact.beginIncremental(
      advertisedBytes: UInt32(X11ClipboardLimits.maximumBytes), format: 32, valueCount: 1,
      bytesAfter: 0) == true)
  for _ in 0..<(X11ClipboardLimits.maximumBytes / chunk.count) {
    #expect(exact.receive(chunk, format: 8, bytesAfter: 0) == .nextChunk)
  }
  var oversized = exact
  #expect(oversized.receive([65], format: 8, bytesAfter: 0) == .invalid)
  if case .complete(let text) = exact.receive([], format: 8, bytesAfter: 0) {
    #expect(text.utf8.count == X11ClipboardLimits.maximumBytes)
  } else {
    Issue.record("Exactly 16 MiB must be accepted")
  }
}

@Test func x11ClipboardINCRSendsEveryByteAndOneAcknowledgedTerminator() {
  let bytes = Array("café 🙂\n".utf8)
  var sender = X11ClipboardSendBuffer(bytes: bytes)
  var received: [UInt8] = []
  var terminators = 0
  while let chunk = sender.nextChunk(maximum: 3) {
    #expect(chunk.count <= 3)
    received.append(contentsOf: chunk)
    if chunk.isEmpty { terminators += 1 }
  }
  #expect(received == bytes)
  #expect(terminators == 1)
  #expect(sender.offset == bytes.count)
  #expect(sender.nextChunk(maximum: 3) == nil)
  var empty = X11ClipboardSendBuffer(bytes: [])
  #expect(empty.nextChunk(maximum: 3) == [])
  #expect(empty.nextChunk(maximum: 3) == nil)
}

@Test @MainActor func x11ClipboardTimestampComparisonHandlesServerClockWrap() {
  #expect(X11Clipboard.isAtOrAfter(5, 5))
  #expect(X11Clipboard.isAtOrAfter(6, 5))
  #expect(!X11Clipboard.isAtOrAfter(4, 5))
  #expect(X11Clipboard.isAtOrAfter(3, UInt32.max - 2))
  #expect(!X11Clipboard.isAtOrAfter(UInt32.max - 2, 3))
}
