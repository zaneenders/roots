import CX11
import Roots
import Testing

@testable import WaylandBridge

// Use a self-contained layout, not the machine's installed XKB data.
private let x11TestKeymap = """
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

private enum X11KeymapTestError: Error { case setupFailed }

@unsafe private func withX11KeyState(_ body: (OpaquePointer) -> Void) throws {
  guard let context = unsafe xkb_context_new(XKB_CONTEXT_NO_FLAGS) else {
    throw X11KeymapTestError.setupFailed
  }
  defer { unsafe xkb_context_unref(context) }
  guard
    let map = unsafe xkb_keymap_new_from_string(
      context, x11TestKeymap, XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS)
  else { throw X11KeymapTestError.setupFailed }
  defer { unsafe xkb_keymap_unref(map) }
  guard let state = unsafe xkb_state_new(map) else { throw X11KeymapTestError.setupFailed }
  defer { unsafe xkb_state_unref(state) }
  unsafe body(state)
}

struct X11KeyResolverTests {
  @Test func nativeXKBCodeUsesLayoutWithoutAddingTheWaylandOffset() throws {
    try unsafe withX11KeyState { state in
      let event = unsafe X11KeyResolver.event(
        state: state, keycode: 24, physicalCode: 24, phase: .pressed)
      #expect(event == KeyEvent(.character("a"), physicalCode: 24))
      let enter = unsafe X11KeyResolver.event(
        state: state, keycode: 36, physicalCode: 36, phase: .released)
      #expect(enter == KeyEvent(.enter, phase: .released, physicalCode: 36))
    }
  }

  @Test func nativeModifiersUnicodeAndNonTextSymbolsArePreserved() throws {
    try unsafe withX11KeyState { state in
      _ = unsafe xkb_state_update_mask(state, 1, 0, 0, 0, 0, 0)
      let shifted = unsafe X11KeyResolver.event(
        state: state, keycode: 24, physicalCode: 24, phase: .repeated)
      #expect(
        shifted == KeyEvent(.character("A"), phase: .repeated, modifiers: .shift, physicalCode: 24))
      _ = unsafe xkb_state_update_mask(state, 4, 0, 0, 0, 0, 0)
      let shortcut = unsafe X11KeyResolver.event(
        state: state, keycode: 24, physicalCode: 24, phase: .pressed)
      #expect(shortcut == KeyEvent(.character("a"), modifiers: .control, physicalCode: 24))
      _ = unsafe xkb_state_update_mask(state, 0, 0, 0, 0, 0, 0)
      let keys = [54, 67, 55, 50, 37, 64, 133, 108, 9, 23].map { code in
        unsafe X11KeyResolver.event(
          state: state, keycode: UInt32(code), physicalCode: UInt32(code), phase: .pressed
        )
        .key
      }
      #expect(
        keys == [
          .character("é"), .function(1), .symbol(0xFE51), .shift, .control, .alt, .super, .altGraph,
          .escape, .tab,
        ])
    }
  }
}
