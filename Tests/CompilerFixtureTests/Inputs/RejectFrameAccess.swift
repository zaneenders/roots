import Roots
// expected-error: 'beginColumn' is inaccessible due to 'internal' protection level

@MainActor func invalid(_ frame: inout UIFrame) {
  frame.beginColumn(in: Region(0, 0, 100, 100))
}
