extension Character {
  // CRLF is one grapheme, so comparing only with LF misses Windows newlines.
  var isTextLineBreak: Bool { self == "\n" || self == "\r\n" || self == "\r" }
}
