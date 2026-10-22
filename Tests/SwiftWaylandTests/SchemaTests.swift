import Foundation
import FoundationXML
import Testing

@testable import SwiftWayland

private final class SchemaParser: NSObject, XMLParserDelegate {
  var requests: [String: [String]] = [:]
  var events: [String: [String]] = [:]
  var destructors: [String: UInt16] = [:]
  var enumValues: [String: [String: UInt32]] = [:]
  private var enumeration: String?
  private var interface = ""
  private var signature = ""
  private var request = false
  private var message = false
  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String] = [:]
  ) {
    switch elementName {
    case "interface":
      interface = attributes["name"] ?? ""
      requests[interface] = []
      events[interface] = []
    case "enum":
      enumeration = interface + "." + (attributes["name"] ?? "")
    case "entry":
      if let enumeration, let name = attributes["name"],
        let value = attributes["value"].flatMap(UInt32.init)
      {
        enumValues[enumeration, default: [:]][name] = value
      }
    case "request", "event":
      signature = ""
      request = elementName == "request"
      if request, attributes["type"] == "destructor" {
        destructors[interface] = UInt16(requests[interface, default: []].count)
      }
      message = true
    case "arg" where message:
      let type = attributes["type"] ?? ""
      if type == "new_id" && attributes["interface"] == nil { signature += "su" }
      signature +=
        [
          "uint": "u", "object": "u", "new_id": "u", "int": "i", "fixed": "i", "string": "s",
          "array": "a", "fd": "h",
        ][
          type] ?? "?"
    default: break
    }
  }
  func parser(
    _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
    qualifiedName: String?
  ) {
    if elementName == "enum" { enumeration = nil }
    if elementName == "request" || elementName == "event" {
      if request {
        requests[interface, default: []].append(signature)
      } else {
        events[interface, default: []].append(signature)
      }
      message = false
    }
  }
}

@Test @MainActor func popupPositionerUsesBottomRightAnchorAndBottomLeftGravity() throws {
  let schema = SchemaParser()
  let url = try #require(
    Bundle.module.url(forResource: "xdg-shell", withExtension: "xml", subdirectory: "Protocols"))
  let parser = try #require(XMLParser(contentsOf: url))
  parser.delegate = schema
  #expect(parser.parse())

  let objects = WaylandObjects()
  let compositor = objects.allocate("wl_compositor")
  let shell = objects.allocate("xdg_wm_base")
  let parent = objects.allocate("xdg_surface")
  let popup = WaylandPopup(
    configuration: .init(x: 20, y: 30, anchorWidth: 40, anchorHeight: 50, width: 120, height: 80),
    scale: 1, compositor: compositor, shell: shell, parent: parent, layerParent: 0, seat: 0,
    serial: nil,
    objects: objects, onDismiss: {})
  defer { popup.close() }
  let (requests, registrations) = try objects.takeRequests()
  let positioner = try #require(registrations.first { $0.value == "xdg_positioner" }?.key)
  for (opcode, enumeration, value): (UInt32, String, String) in [
    (3, "anchor", "bottom_right"), (4, "gravity", "bottom_left"),
  ] {
    let request = try #require(
      requests.first {
        $0.bytes.getInteger(at: 0, endianness: .host, as: UInt32.self) == positioner
          && $0.bytes.getInteger(at: 4, endianness: .host, as: UInt32.self) == (12 << 16 | opcode)
      })
    let expected = try #require(schema.enumValues["xdg_positioner." + enumeration]?[value])
    #expect(request.bytes.getInteger(at: 8, endianness: .host, as: UInt32.self) == expected)
  }
}

@Test func swiftWireSchemaMatchesPinnedProtocolXML() throws {
  let schema = SchemaParser()
  for name in [
    "wayland", "xdg-shell", "wlr-layer-shell-unstable-v1", "linux-dmabuf-v1",
    "idle-inhibit-unstable-v1",
  ] {
    let url = try #require(
      Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "Protocols"))
    let parser = try #require(XMLParser(contentsOf: url))
    parser.delegate = schema
    #expect(parser.parse())
  }
  let inputEnums: [String: [String: UInt32]] = [
    "wl_pointer.axis": [
      "vertical_scroll": WaylandPointerAxis.verticalScroll.rawValue,
      "horizontal_scroll": WaylandPointerAxis.horizontalScroll.rawValue,
    ],
    "wl_pointer.axis_source": [
      "wheel": WaylandPointerAxisSource.wheel.rawValue,
      "finger": WaylandPointerAxisSource.finger.rawValue,
      "continuous": WaylandPointerAxisSource.continuous.rawValue,
      "wheel_tilt": WaylandPointerAxisSource.wheelTilt.rawValue,
    ],
    "wl_pointer.button_state": [
      "released": WaylandPointerButtonState.released.rawValue,
      "pressed": WaylandPointerButtonState.pressed.rawValue,
    ],
    "wl_keyboard.keymap_format": [
      "no_keymap": WaylandKeyboardKeymapFormat.noKeymap.rawValue,
      "xkb_v1": WaylandKeyboardKeymapFormat.xkbV1.rawValue,
    ],
  ]
  for (name, values) in inputEnums { #expect(schema.enumValues[name] == values) }
  for (name, events) in WireSchema.events { #expect(schema.events[name] == events) }
  for (name, requests) in WireSchema.requests {
    #expect(schema.requests[name] == requests)
    #expect(schema.destructors[name] == WireSchema.destructors[name])
  }
}
