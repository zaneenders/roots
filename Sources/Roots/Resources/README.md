# Generated font resources

`FontAtlasPlugin` generates both atlases into `Bundle.module`; neither atlas is checked in.

```text
NotoSansMono + SymbolGlyphs.swift + AtlasCoverage ─► FontAtlasGenerator ─► CATL v1
NotoColorEmoji + EmojiSequences                  ─► EmojiAtlasGenerator ─► EATL v2

Character ─► ASCII/text or default-emoji/VS16 lookup ─► DrawRect(glyphUV, colorGlyph)
                                                      │
                                  CPU / GLES / Metal ─┘
```

| | `FontAtlas` | `EmojiAtlas` |
|---|---|---|
| Pixel format | coverage `UInt8` | premultiplied BGRA `UInt8 × 4` |
| Columns | 32 | 64 |
| Cell / glyph box | 66×90 / 60×84 | 42×48 / 36×42 |
| Padding | 3 | 3 |
| Mapping | scalar → cell | UTF-8 extended grapheme → deduplicated cell |
| Missing glyph | U+FFFD, log once | fall through to text/replacement |

```swift
// Both headers and records use little-endian UInt32.
// CATL v1: magic, version, width, height, count, scalars[count], coverage mip chain.
// EATL v2: magic, version, width, height, count, cells,
//          (utf8Count, utf8Bytes, cellIndex)[count], BGRA mip chain.
// Mips: 2×2 box filter, (sum + 2) >> 2, dimensions max(1, previous / 2).
```

Monochrome rasterization: hinted 60 px, baseline row 68, pen column 3.
Missing typeface symbols: package-authored geometry in `SymbolGlyphs.swift`, 4× supersampling.
Braille dots: 6×9, columns 12/26, rows 18/36/54/72; edge coverage preserved.
Text uses `MonospaceFont.advance == size * 0.6`; each color emoji uses two advances, with a gutter.
`MonospaceFont.columnWidth(of:)` drives measurement, painting, wrapping and hit-testing.
Flags, modifiers, keycaps and font-covered ZWJ sequences remain one quad per `Character`.
VS16 selects emoji; VS15 selects available text. No kerning, bidi or contextual shaping.
