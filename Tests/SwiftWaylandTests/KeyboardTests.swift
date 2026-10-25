import Foundation
import Glibc
import Testing

@testable import SwiftWayland

private let keymap = """
  xkb_keymap {
    xkb_keycodes "test" {
      minimum = 8; maximum = 255;
      <AD01> = 24; <LFSH> = 50; <LCTL> = 37; <LALT> = 64;
      <SPCE> = 65; <RTRN> = 36; <BKSP> = 22; <LEFT> = 113;
      <ESC> = 9; <TAB> = 23; <LWIN> = 133; <RALT> = 108;
      <AB03> = 54; <FK01> = 67; <DEAD> = 55;
    };
    xkb_types "test" {
      type "ONE_LEVEL" { modifiers = None; map[None] = Level1; };
      type "TWO_LEVEL" { modifiers = Shift; map[None] = Level1; map[Shift] = Level2; };
    };
    xkb_compatibility "test" {};
    xkb_symbols "test" {
      key <AD01> { type = "TWO_LEVEL", [ a, A ] };
      key <LFSH> { [ Shift_L ] }; modifier_map Shift { <LFSH> };
      key <LCTL> { [ Control_L ] }; modifier_map Control { <LCTL> };
      key <LALT> { [ Alt_L ] }; modifier_map Mod1 { <LALT> };
      key <SPCE> { [ space ] };
      key <RTRN> { [ Return ] };
      key <BKSP> { [ BackSpace ] };
      key <LEFT> { [ Left ] };
      key <ESC> { [ Escape ] };
      key <TAB> { [ Tab ] };
      key <LWIN> { [ Super_L ] }; modifier_map Mod4 { <LWIN> };
      key <RALT> { [ ISO_Level3_Shift ] }; modifier_map Mod5 { <RALT> };
      key <AB03> { [ eacute ] };
      key <FK01> { [ F1 ] };
      key <DEAD> { [ dead_acute ] };
    };
  };
  """

private func event(
  _ key: WaylandKey, code: UInt32, phase: WaylandKeyPhase = .pressed,
  modifiers: WaylandKeyModifiers = []
) -> WaylandKeyEvent {
  WaylandKeyEvent(key, phase: phase, modifiers: modifiers, physicalCode: code)
}

private func withKeymapFile(_ bytes: Data, _ body: (Int32) throws -> Void) throws {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try bytes.write(to: url)
  defer { try? FileManager.default.removeItem(at: url) }
  let fd = unsafe open(url.path, O_RDWR)
  try #require(fd >= 0)
  defer { _ = close(fd) }
  try body(fd)
}

@Test func keysUseTheLayoutAndPreserveModifiersPhysicalIdentityAndReleaseOrder() {
  var keyboard = Keyboard()
  keyboard.load(keymap: keymap)
  var input = WaylandInput(width: 100, height: 80)
  keyboard.key(16, pressed: true, input: &input)
  keyboard.modifiers(depressed: 1, latched: 0, locked: 0, group: 0)
  keyboard.key(16, pressed: true, input: &input)
  keyboard.modifiers(depressed: 0, latched: 0, locked: 0, group: 0)
  keyboard.key(57, pressed: true, input: &input)
  keyboard.key(14, pressed: true, input: &input)
  keyboard.key(105, pressed: true, input: &input)
  keyboard.key(28, pressed: true, input: &input)
  keyboard.key(16, pressed: false, input: &input)
  #expect(
    input.keyEvents == [
      event(.character("a"), code: 16), event(.character("A"), code: 16, modifiers: .shift),
      event(.character(" "), code: 57), event(.backspace, code: 14), event(.left, code: 105),
      event(.enter, code: 28), event(.character("a"), code: 16, phase: .released)
    ])
  input.resetEdges()
  #expect(input.keyEvents.isEmpty)
  keyboard.key(16, pressed: true, input: &input)
  keyboard.leave(input: &input)
  #expect(input.keyEvents.isEmpty)
  #expect(input.focusLost)
  input.resetEdges()
  #expect(!input.focusLost)
}

@Test func shortcutsReachTheApplicationWithoutControlCharacterConversion() {
  var keyboard = Keyboard()
  keyboard.load(keymap: keymap)
  var input = WaylandInput(width: 100, height: 80)
  for (mask, modifier): (UInt32, WaylandKeyModifiers) in [
    (4, .control), (8, .alt), (64, .super), (128, .altGraph)
  ] {
    keyboard.modifiers(depressed: mask, latched: 0, locked: 0, group: 0)
    keyboard.key(16, pressed: true, input: &input)
    keyboard.key(28, pressed: true, input: &input)
    #expect(
      input.keyEvents == [
        event(.character("a"), code: 16, modifiers: modifier),
        event(.enter, code: 28, modifiers: modifier)
      ])
    input.resetEdges()
  }
}

@Test func nonASCIIAndNonTextKeysAreNotDiscarded() {
  var keyboard = Keyboard()
  keyboard.load(keymap: keymap)
  var input = WaylandInput(width: 100, height: 80)
  for code: UInt32 in [46, 59, 47, 42, 29, 56, 125, 100, 1, 15] {
    keyboard.key(code, pressed: true, input: &input)
  }
  #expect(
    input.keyEvents.map(\.key) == [
      .character("é"), .function(1), .symbol(0xFE51), .shift, .control, .alt, .super, .altGraph,
      .escape, .tab
    ])
  #expect(input.keyEvents.allSatisfy { $0.phase == .pressed })
}

@Test func heldKeysRepeatAfterDelayWithCurrentModifiersAndStopOnReleaseOrFocusLoss() {
  var keyboard = Keyboard()
  keyboard.load(keymap: keymap)
  keyboard.repeatInfo(rate: 20, delay: 200)
  var input = WaylandInput(width: 100, height: 80)
  let start = ContinuousClock.now
  keyboard.key(16, pressed: true, input: &input, now: start)
  #expect(keyboard.isRepeating == true)
  input.resetEdges()
  keyboard.repeatKeys(input: &input, now: start.advanced(by: .milliseconds(199)))
  #expect(input.keyEvents.isEmpty)
  keyboard.repeatKeys(input: &input, now: start.advanced(by: .milliseconds(300)))
  #expect(
    input.keyEvents
      == Array(repeating: event(.character("a"), code: 16, phase: .repeated), count: 3))
  input.resetEdges()
  keyboard.key(42, pressed: true, input: &input, now: start)
  keyboard.modifiers(depressed: 1, latched: 0, locked: 0, group: 0)
  keyboard.repeatKeys(input: &input, now: start.advanced(by: .milliseconds(350)))
  #expect(
    input.keyEvents == [
      event(.shift, code: 42),
      event(.character("A"), code: 16, phase: .repeated, modifiers: .shift)
    ])
  input.resetEdges()
  keyboard.key(16, pressed: false, input: &input)
  keyboard.repeatKeys(input: &input, now: start.advanced(by: .seconds(1)))
  #expect(
    input.keyEvents == [event(.character("A"), code: 16, phase: .released, modifiers: .shift)])
  keyboard.key(16, pressed: true, input: &input, now: start)
  keyboard.leave(input: &input)
  #expect(keyboard.isRepeating == false)
  keyboard.repeatKeys(input: &input, now: start.advanced(by: .seconds(1)))
  #expect(input.keyEvents.isEmpty)
}

@Test func backendRepeatsEnterWithoutTreatingItAsSubmitAndBoundsCatchUp() {
  var keyboard = Keyboard()
  keyboard.load(keymap: keymap)
  keyboard.repeatInfo(rate: 20, delay: 200)
  var input = WaylandInput(width: 100, height: 80)
  let start = ContinuousClock.now
  keyboard.key(28, pressed: true, input: &input, now: start)
  input.resetEdges()
  keyboard.repeatKeys(input: &input, now: start.advanced(by: .milliseconds(200)))
  #expect(input.keyEvents == [event(.enter, code: 28, phase: .repeated)])
  keyboard.key(16, pressed: true, input: &input, now: start)
  input.resetEdges()
  keyboard.repeatKeys(input: &input, now: start.advanced(by: .seconds(10)))
  #expect(
    input.keyEvents
      == Array(repeating: event(.character("a"), code: 16, phase: .repeated), count: 32))
  input.resetEdges()
  keyboard.repeatInfo(rate: 0, delay: 200)
  keyboard.repeatKeys(input: &input, now: start.advanced(by: .seconds(11)))
  #expect(input.keyEvents.isEmpty)
}

@Test func compositorKeymapLoadsFromAnOwnedFileDescriptorAndMissingMapKeepsPhysicalKeys() throws {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let bytes = Data((keymap + "\0").utf8)
  try bytes.write(to: url)
  defer { try? FileManager.default.removeItem(at: url) }
  let fd = unsafe open(url.path, O_RDONLY)
  #expect(fd >= 0)
  guard fd >= 0 else { return }
  defer { _ = close(fd) }
  var keyboard = Keyboard()
  keyboard.load(format: 1, fd: fd, size: UInt32(bytes.count))
  var input = WaylandInput(width: 100, height: 80)
  keyboard.key(16, pressed: true, input: &input)
  #expect(input.keyEvents == [event(.character("a"), code: 16)])
  keyboard.load(format: 0, fd: fd, size: UInt32(bytes.count))
  input.resetEdges()
  keyboard.key(16, pressed: true, input: &input)
  keyboard.key(UInt32.max, pressed: false, input: &input)
  #expect(
    input.keyEvents == [
      event(.symbol(0), code: 16), event(.symbol(0), code: .max, phase: .released)
    ])
}

@Test(arguments: [UInt32(1), 15]) func otherNonmodifierKeysReplaceHeldTyping(code: UInt32) {
  var keyboard = Keyboard()
  keyboard.load(keymap: keymap)
  keyboard.repeatInfo(rate: 20, delay: 200)
  var input = WaylandInput(width: 100, height: 80)
  let start = ContinuousClock.now
  keyboard.key(16, pressed: true, input: &input, now: start)
  keyboard.key(code, pressed: true, input: &input, now: start)
  #expect(input.keyEvents.last?.key == (code == 1 ? .escape : .tab))
  input.resetEdges()
  keyboard.repeatKeys(input: &input, now: start.advanced(by: .seconds(1)))
  #expect(!input.keyEvents.contains { $0.physicalCode == 16 })
}

@Test func releasingAnotherKeyDoesNotCancelRepeatButKeymapReloadDoes() {
  var keyboard = Keyboard()
  keyboard.load(keymap: keymap)
  keyboard.repeatInfo(rate: 20, delay: 200)
  var input = WaylandInput(width: 100, height: 80)
  let start = ContinuousClock.now
  keyboard.key(16, pressed: true, input: &input, now: start)
  input.resetEdges()
  keyboard.key(42, pressed: false, input: &input, now: start)
  keyboard.repeatKeys(input: &input, now: start.advanced(by: .milliseconds(200)))
  #expect(
    input.keyEvents == [
      event(.shift, code: 42, phase: .released), event(.character("a"), code: 16, phase: .repeated)
    ])
  input.resetEdges()
  keyboard.load(keymap: keymap)
  keyboard.repeatKeys(input: &input, now: start.advanced(by: .seconds(1)))
  #expect(input.keyEvents.isEmpty)
}

@Test func keyboardLeaveClearsPendingKeysAndRepeat() {
  var keyboard = Keyboard()
  keyboard.load(keymap: keymap)
  keyboard.repeatInfo(rate: 20, delay: 200)
  var input = WaylandInput(width: 100, height: 80)
  let start = ContinuousClock.now
  for code: UInt32 in [15, 57, 1, 16] {
    keyboard.key(code, pressed: true, input: &input, now: start)
  }
  #expect(input.keyEvents.map(\.key) == [.tab, .character(" "), .escape, .character("a")])
  keyboard.leave(input: &input)
  #expect(input.keyEvents.isEmpty)
  keyboard.repeatKeys(input: &input, now: start.advanced(by: .seconds(1)))
  #expect(input.keyEvents.isEmpty)
}

@Test(arguments: [0, 1, 8_192]) func shortKeymapFileClearsLayoutAndRepeat(extraBytes: Int) throws {
  let bytes = Data((keymap + "\0").utf8)
  try withKeymapFile(bytes) { fd in
    var keyboard = Keyboard()
    keyboard.load(keymap: keymap)
    keyboard.repeatInfo(rate: 20, delay: 0)
    var input = WaylandInput(width: 100, height: 80)
    let start = ContinuousClock.now
    keyboard.key(16, pressed: true, input: &input, now: start)
    input.resetEdges()
    #expect(ftruncate(fd, off_t(bytes.count - 1)) == 0)
    keyboard.load(format: 1, fd: fd, size: UInt32(bytes.count + extraBytes))
    keyboard.repeatKeys(input: &input, now: start.advanced(by: .seconds(1)))
    #expect(input.keyEvents.isEmpty)
    keyboard.key(16, pressed: true, input: &input)
    #expect(input.keyEvents == [event(.symbol(0), code: 16)])
    #expect(fcntl(fd, F_GETFD) >= 0)
  }
}

@Test func keymapReadStartsAtZeroWithoutChangingDescriptorOffset() throws {
  let bytes = Data(keymap.utf8)
  try withKeymapFile(bytes) { fd in
    let position = off_t(bytes.count / 2)
    #expect(lseek(fd, position, SEEK_SET) == position)
    var keyboard = Keyboard()
    keyboard.load(format: 1, fd: fd, size: UInt32(bytes.count))
    #expect(lseek(fd, 0, SEEK_CUR) == position)
    var input = WaylandInput(width: 100, height: 80)
    keyboard.key(16, pressed: true, input: &input)
    #expect(input.keyEvents == [event(.character("a"), code: 16)])
  }
}

@Test func keymapParserSeesTheWholeBufferIncludingEmbeddedNULAndInvalidBytes() throws {
  for suffix: [UInt8] in [[0, 65], [255]] {
    var bytes = Data(keymap.utf8)
    bytes.append(contentsOf: suffix)
    try withKeymapFile(bytes) { fd in
      var keyboard = Keyboard()
      keyboard.load(keymap: keymap)
      keyboard.repeatInfo(rate: 20, delay: 0)
      var input = WaylandInput(width: 100, height: 80)
      let started = ContinuousClock.now
      keyboard.key(16, pressed: true, input: &input, now: started)
      input.resetEdges()
      keyboard.load(format: 1, fd: fd, size: UInt32(bytes.count))
      keyboard.repeatKeys(input: &input, now: started.advanced(by: .seconds(1)))
      #expect(input.keyEvents.isEmpty)
      keyboard.key(16, pressed: true, input: &input)
      #expect(input.keyEvents == [event(.symbol(0), code: 16)])
      #expect(fcntl(fd, F_GETFD) >= 0)
    }
  }
}

@Test(arguments: [UInt32(0), Keyboard.maximumKeymapSize + 1, UInt32.max])
func invalidKeymapSizeClearsTheOldLayout(size: UInt32) throws {
  try withKeymapFile(Data((keymap + "\0").utf8)) { fd in
    var keyboard = Keyboard()
    keyboard.load(keymap: keymap)
    keyboard.load(format: 1, fd: fd, size: size)
    var input = WaylandInput(width: 100, height: 80)
    keyboard.key(16, pressed: true, input: &input)
    #expect(input.keyEvents == [event(.symbol(0), code: 16)])
  }
}

@Test func invalidAndNonseekableKeymapDescriptorsDoNotBlock() throws {
  var keyboard = Keyboard()
  keyboard.load(keymap: keymap)
  keyboard.load(format: 1, fd: -1, size: 1)
  var input = WaylandInput(width: 100, height: 80)
  keyboard.key(16, pressed: true, input: &input)
  #expect(input.keyEvents == [event(.symbol(0), code: 16)])

  var descriptors: [Int32] = [0, 0]
  try #require(unsafe pipe(&descriptors) == 0)
  defer {
    _ = close(descriptors[0])
    _ = close(descriptors[1])
  }
  keyboard.load(keymap: keymap)
  keyboard.load(format: 1, fd: descriptors[0], size: 1)
  input.resetEdges()
  keyboard.key(16, pressed: true, input: &input)
  #expect(input.keyEvents == [event(.symbol(0), code: 16)])
}

@Test func movingKeyboardTransfersItsLayoutAndRepeatState() {
  var original = Keyboard()
  original.load(keymap: keymap)
  original.repeatInfo(rate: 20, delay: 0)
  var input = WaylandInput(width: 100, height: 80)
  let start = ContinuousClock.now
  original.key(16, pressed: true, input: &input, now: start)
  input.resetEdges()
  var moved = consume original
  moved.repeatKeys(input: &input, now: start)
  #expect(input.keyEvents == [event(.character("a"), code: 16, phase: .repeated)])
  moved.load(keymap: keymap)
  input.resetEdges()
  moved.key(16, pressed: true, input: &input)
  #expect(input.keyEvents == [event(.character("a"), code: 16)])
}

@MainActor func loadTestKeymap(_ connection: WaylandConnection, keyboard: UInt32) throws {
  let bytes = Data((keymap + "\0").utf8)
  try withKeymapFile(bytes) { fd in
    try connection.receive(
      .init(
        object: keyboard, opcode: 0,
        arguments: [.uint(1), .fd(try WireDescriptor.duplicate(fd)), .uint(UInt32(bytes.count))]))
  }
}

@Test func deadKeysComposeTextWithoutChangingPhysicalKeyEvents() {
  var keyboard = Keyboard(locale: "en_US.UTF-8")
  keyboard.load(keymap: keymap)
  keyboard.repeatInfo(rate: 20, delay: 200)
  var input = WaylandInput(width: 10, height: 10)
  let now = ContinuousClock.now
  keyboard.key(47, pressed: true, input: &input, now: now)
  keyboard.key(47, pressed: false, input: &input, now: now)
  #expect(input.textEvents.isEmpty)
  keyboard.key(16, pressed: true, input: &input, now: now)
  #expect(input.textEvents == [.init(committed: "á")])
  #expect(input.keyEvents.map(\.physicalCode) == [47, 47, 16])
  #expect(input.keyEvents.last?.key == .character("a"))
  input.resetEdges()
  keyboard.repeatKeys(input: &input, now: now.advanced(by: .milliseconds(200)))
  #expect(input.textEvents == [.init(committed: "á")])
}

@Test func composeCancellationFocusLossAndShortcutsDoNotInsertText() {
  var keyboard = Keyboard(locale: "en_US.UTF-8")
  keyboard.load(keymap: keymap)
  var input = WaylandInput(width: 10, height: 10)
  keyboard.key(47, pressed: true, input: &input)
  keyboard.key(1, pressed: true, input: &input)
  #expect(input.textEvents.isEmpty)
  keyboard.key(16, pressed: true, input: &input)
  #expect(input.textEvents == [.init(committed: "a")])
  keyboard.key(47, pressed: true, input: &input)
  keyboard.leave(input: &input)
  keyboard.key(16, pressed: true, input: &input)
  #expect(input.textEvents == [.init(committed: "a")])
  input.resetEdges()
  keyboard.modifiers(depressed: 4, latched: 0, locked: 0, group: 0)
  keyboard.key(16, pressed: true, input: &input)
  #expect(input.textEvents.isEmpty)
  #expect(input.keyEvents.last?.modifiers == .control)
}

@Test func composeKeySequenceAndRepeatedTextRespectShortcutModifiers() {
  var keyboard = Keyboard(locale: "en_US.UTF-8")
  let map = keymap.replacingOccurrences(of: "[ F1 ]", with: "[ Multi_key ]")
  keyboard.load(keymap: map)
  keyboard.repeatInfo(rate: 20, delay: 200)
  var input = WaylandInput(width: 10, height: 10)
  let now = ContinuousClock.now
  for key: UInt32 in [59, 16, 16] { keyboard.key(key, pressed: true, input: &input, now: now) }
  #expect(input.textEvents == [.init(committed: "å")])
  input.resetEdges()
  keyboard.modifiers(depressed: 4, latched: 0, locked: 0, group: 0)
  keyboard.repeatKeys(input: &input, now: now.advanced(by: .milliseconds(200)))
  #expect(input.textEvents.isEmpty)
  #expect(input.keyEvents.last?.modifiers == .control)
}

@Test func composeCanCommitMultipleUnicodeScalars() {
  var keyboard = Keyboard(locale: "en_US.UTF-8")
  keyboard.load(keymap: keymap.replacingOccurrences(of: "[ a, A ]", with: "[ j, J ]"))
  var input = WaylandInput(width: 10, height: 10)
  keyboard.key(47, pressed: true, input: &input)
  keyboard.key(16, pressed: true, input: &input)
  #expect(input.textEvents.first?.committed?.unicodeScalars.count == 2)
  #expect(input.textEvents.first?.committed == "j\u{301}")
}
