import Foundation
import FoundationXML
import Testing

@testable import SwiftWayland

private final class SchemaParser: NSObject, XMLParserDelegate {
  var requests: [String: [WireSchema.Message]] = [:]
  var events: [String: [WireSchema.Message]] = [:]
  var versions: [String: UInt32] = [:]
  var destructors: [String: UInt16] = [:]
  var enumValues: [String: [String: UInt32]] = [:]
  private var enumeration: String?
  private var interface = ""
  private var signature = ""
  private var messageName = ""
  private var since: UInt32 = 1
  private var request = false
  private var message = false
  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String] = [:]
  ) {
    switch elementName {
    case "interface":
      interface = attributes["name"] ?? ""
      versions[interface] = UInt32(attributes["version"] ?? "1")
      requests[interface] = []
      events[interface] = []
    case "enum":
      enumeration = interface + "." + (attributes["name"] ?? "")
    case "entry":
      if let enumeration, let name = attributes["name"],
        let value = attributes["value"].flatMap({ raw in
          raw.hasPrefix("0x") ? UInt32(raw.dropFirst(2), radix: 16) : UInt32(raw)
        })
      {
        enumValues[enumeration, default: [:]][name] = value
      }
    case "request", "event":
      signature = ""
      messageName = attributes["name"] ?? ""
      since = UInt32(attributes["since"] ?? "1") ?? 1
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
        requests[interface, default: []].append(.init(messageName, signature, since: since))
      } else {
        events[interface, default: []].append(.init(messageName, signature, since: since))
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
  let compositor = objects.allocate("wl_compositor", version: 6)
  let shell = objects.allocate("xdg_wm_base")
  let parent = objects.allocate("xdg_surface")
  let popup = WaylandPopup(
    configuration: .init(x: 20, y: 30, anchorWidth: 40, anchorHeight: 50, width: 120, height: 80),
    scale: 1, compositor: compositor, shell: shell, parent: parent, layerParent: 0, seat: 0,
    serial: nil,
    objects: objects, onDismiss: {})
  defer { popup.close() }
  let requests = try objects.takeRequests()
  let registrations = objects.interfaces
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
    "cursor-shape-v1", "text-input-unstable-v3", "wayland", "xdg-shell",
    "wlr-layer-shell-unstable-v1", "linux-dmabuf-v1",
    "idle-inhibit-unstable-v1", "fractional-scale-v1", "viewporter",
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
  let surfaceEnums: [(String, String, UInt32)] = [
    ("wl_output.transform", "flipped_180", UInt32(WaylandBufferTransform.flipped180.rawValue)),
    ("xdg_positioner.anchor", "bottom_right", WaylandPositionerAnchor.bottomRight.rawValue),
    ("xdg_positioner.gravity", "bottom_left", WaylandPositionerGravity.bottomLeft.rawValue),
    (
      "xdg_positioner.constraint_adjustment", "slide_x", WaylandConstraintAdjustment.slideX.rawValue
    ),
    (
      "xdg_positioner.constraint_adjustment", "slide_y", WaylandConstraintAdjustment.slideY.rawValue
    ),
    ("xdg_positioner.constraint_adjustment", "flip_y", WaylandConstraintAdjustment.flipY.rawValue),
    ("zwlr_layer_surface_v1.anchor", "top", WaylandLayerAnchor.top.rawValue),
    ("zwlr_layer_surface_v1.anchor", "left", WaylandLayerAnchor.left.rawValue),
    ("zwlr_layer_surface_v1.anchor", "right", WaylandLayerAnchor.right.rawValue),
    ("zwlr_layer_shell_v1.layer", "top", WaylandLayer.top.rawValue),
    (
      "zwlr_layer_surface_v1.keyboard_interactivity", "none",
      WaylandKeyboardInteractivity.none.rawValue
    ),
  ]
  for (enumeration, entry, value) in surfaceEnums {
    #expect(schema.enumValues[enumeration]?[entry] == value)
  }
  for shape in WaylandCursorShape.allCases {
    #expect(
      schema.enumValues["wp_cursor_shape_device_v1.shape"]?.values.contains(shape.rawValue) == true)
  }
  #expect(
    schema.enumValues["zwp_text_input_v3.content_purpose"]?["password"]
      == WaylandTextInputState.Purpose.password.rawValue)
  #expect(
    schema.enumValues["zwp_text_input_v3.content_hint"]?["sensitive_data"]
      == WaylandTextInputState.Hints.sensitiveData.rawValue)
  for (name, values) in inputEnums { #expect(schema.enumValues[name] == values) }
  for (name, events) in WireSchema.events {
    #expect(schema.events[name] == events)
    #expect(schema.versions[name] == WireSchema.versions[name])
  }
  for (name, requests) in WireSchema.requests {
    #expect(schema.requests[name] == requests)
    #expect(schema.destructors[name] == WireSchema.destructors[name])
  }
}

@Test func typedRequestsMatchSchemaNamesAndOpcodeOrder() {
  func check<R: WireRequest>(_ type: R.Type) {
    let messages = WireSchema.requests[R.interface] ?? []
    #expect(R.allCases.count == messages.count)
    for (index, request) in R.allCases.enumerated() {
      #expect(Int(request.rawValue) == index)
      let name = messages[index].name.split(separator: "_").enumerated().map {
        $0.offset == 0 ? String($0.element) : $0.element.capitalized
      }.joined()
      #expect(String(describing: request) == name)
    }
  }
  check(WpCursorShapeManagerV1Request.self)
  check(WpCursorShapeDeviceV1Request.self)
  check(ZwpTextInputManagerV3Request.self)
  check(ZwpTextInputV3Request.self)
  check(WpViewporterRequest.self)
  check(WpViewportRequest.self)
  check(WpFractionalScaleManagerV1Request.self)
  check(WpFractionalScaleV1Request.self)
  check(WlCompositorRequest.self)
  check(WlBufferRequest.self)
  check(WlDataOfferRequest.self)
  check(WlDataSourceRequest.self)
  check(WlDataDeviceRequest.self)
  check(WlDataDeviceManagerRequest.self)
  check(WlSurfaceRequest.self)
  check(WlSeatRequest.self)
  check(WlPointerRequest.self)
  check(WlKeyboardRequest.self)
  check(WlOutputRequest.self)
  check(WlRegionRequest.self)
  check(XdgWmBaseRequest.self)
  check(XdgPositionerRequest.self)
  check(XdgSurfaceRequest.self)
  check(XdgToplevelRequest.self)
  check(XdgPopupRequest.self)
  check(ZwlrLayerShellV1Request.self)
  check(ZwlrLayerSurfaceV1Request.self)
  check(ZwpIdleInhibitManagerV1Request.self)
  check(ZwpIdleInhibitorV1Request.self)
  check(ZwpLinuxDmabufFeedbackV1Request.self)
  check(ZwpLinuxDmabufV1Request.self)
  check(ZwpLinuxBufferParamsV1Request.self)
  check(WlDisplayRequest.self)
  check(WlRegistryRequest.self)
}
