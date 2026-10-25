protocol WireRequest: RawRepresentable, CaseIterable where RawValue == UInt16 {
  static var interface: String { get }
}

enum WpCursorShapeManagerV1Request: UInt16, WireRequest {
  static let interface = "wp_cursor_shape_manager_v1"
  case destroy = 0
  case getPointer = 1
  case getTabletToolV2 = 2
}

enum WpCursorShapeDeviceV1Request: UInt16, WireRequest {
  static let interface = "wp_cursor_shape_device_v1"
  case destroy = 0
  case setShape = 1
}

enum ZwpTextInputManagerV3Request: UInt16, WireRequest {
  static let interface = "zwp_text_input_manager_v3"
  case destroy = 0
  case getTextInput = 1
}

enum ZwpTextInputV3Request: UInt16, WireRequest {
  static let interface = "zwp_text_input_v3"
  case destroy = 0
  case enable = 1
  case disable = 2
  case setSurroundingText = 3
  case setTextChangeCause = 4
  case setContentType = 5
  case setCursorRectangle = 6
  case commit = 7
  case setAvailableActions = 8
  case showInputPanel = 9
  case hideInputPanel = 10
}

enum WpViewporterRequest: UInt16, WireRequest {
  static let interface = "wp_viewporter"
  case destroy = 0
  case getViewport = 1
}

enum WpViewportRequest: UInt16, WireRequest {
  static let interface = "wp_viewport"
  case destroy = 0
  case setSource = 1
  case setDestination = 2
}

enum WpFractionalScaleManagerV1Request: UInt16, WireRequest {
  static let interface = "wp_fractional_scale_manager_v1"
  case destroy = 0
  case getFractionalScale = 1
}

enum WpFractionalScaleV1Request: UInt16, WireRequest {
  static let interface = "wp_fractional_scale_v1"
  case destroy = 0
}

enum WlCompositorRequest: UInt16, WireRequest {
  static let interface = "wl_compositor"
  case createSurface = 0
  case createRegion = 1
  case release = 2
}

enum WlBufferRequest: UInt16, WireRequest {
  static let interface = "wl_buffer"
  case destroy = 0
}

enum WlDataOfferRequest: UInt16, WireRequest {
  static let interface = "wl_data_offer"
  case accept = 0
  case receive = 1
  case destroy = 2
  case finish = 3
  case setActions = 4
}

enum WlDataSourceRequest: UInt16, WireRequest {
  static let interface = "wl_data_source"
  case offer = 0
  case destroy = 1
  case setActions = 2
}

enum WlDataDeviceRequest: UInt16, WireRequest {
  static let interface = "wl_data_device"
  case startDrag = 0
  case setSelection = 1
  case release = 2
}

enum WlDataDeviceManagerRequest: UInt16, WireRequest {
  static let interface = "wl_data_device_manager"
  case createDataSource = 0
  case getDataDevice = 1
  case release = 2
}

enum WlSurfaceRequest: UInt16, WireRequest {
  static let interface = "wl_surface"
  case destroy = 0
  case attach = 1
  case damage = 2
  case frame = 3
  case setOpaqueRegion = 4
  case setInputRegion = 5
  case commit = 6
  case setBufferTransform = 7
  case setBufferScale = 8
  case damageBuffer = 9
  case offset = 10
  case getRelease = 11
}

enum WlSeatRequest: UInt16, WireRequest {
  static let interface = "wl_seat"
  case getPointer = 0
  case getKeyboard = 1
  case getTouch = 2
  case release = 3
}

enum WlPointerRequest: UInt16, WireRequest {
  static let interface = "wl_pointer"
  case setCursor = 0
  case release = 1
}

enum WlKeyboardRequest: UInt16, WireRequest {
  static let interface = "wl_keyboard"
  case release = 0
}

enum WlOutputRequest: UInt16, WireRequest {
  static let interface = "wl_output"
  case release = 0
}

enum WlRegionRequest: UInt16, WireRequest {
  static let interface = "wl_region"
  case destroy = 0
  case add = 1
  case subtract = 2
}

enum XdgWmBaseRequest: UInt16, WireRequest {
  static let interface = "xdg_wm_base"
  case destroy = 0
  case createPositioner = 1
  case getXdgSurface = 2
  case pong = 3
}

enum XdgPositionerRequest: UInt16, WireRequest {
  static let interface = "xdg_positioner"
  case destroy = 0
  case setSize = 1
  case setAnchorRect = 2
  case setAnchor = 3
  case setGravity = 4
  case setConstraintAdjustment = 5
  case setOffset = 6
  case setReactive = 7
  case setParentSize = 8
  case setParentConfigure = 9
}

enum XdgSurfaceRequest: UInt16, WireRequest {
  static let interface = "xdg_surface"
  case destroy = 0
  case getToplevel = 1
  case getPopup = 2
  case setWindowGeometry = 3
  case ackConfigure = 4
}

enum XdgToplevelRequest: UInt16, WireRequest {
  static let interface = "xdg_toplevel"
  case destroy = 0
  case setParent = 1
  case setTitle = 2
  case setAppId = 3
  case showWindowMenu = 4
  case move = 5
  case resize = 6
  case setMaxSize = 7
  case setMinSize = 8
  case setMaximized = 9
  case unsetMaximized = 10
  case setFullscreen = 11
  case unsetFullscreen = 12
  case setMinimized = 13
}

enum XdgPopupRequest: UInt16, WireRequest {
  static let interface = "xdg_popup"
  case destroy = 0
  case grab = 1
  case reposition = 2
}

enum ZwlrLayerShellV1Request: UInt16, WireRequest {
  static let interface = "zwlr_layer_shell_v1"
  case getLayerSurface = 0
  case destroy = 1
}

enum ZwlrLayerSurfaceV1Request: UInt16, WireRequest {
  static let interface = "zwlr_layer_surface_v1"
  case setSize = 0
  case setAnchor = 1
  case setExclusiveZone = 2
  case setMargin = 3
  case setKeyboardInteractivity = 4
  case getPopup = 5
  case ackConfigure = 6
  case destroy = 7
  case setLayer = 8
}

enum ZwpIdleInhibitManagerV1Request: UInt16, WireRequest {
  static let interface = "zwp_idle_inhibit_manager_v1"
  case destroy = 0
  case createInhibitor = 1
}

enum ZwpIdleInhibitorV1Request: UInt16, WireRequest {
  static let interface = "zwp_idle_inhibitor_v1"
  case destroy = 0
}

enum ZwpLinuxDmabufFeedbackV1Request: UInt16, WireRequest {
  static let interface = "zwp_linux_dmabuf_feedback_v1"
  case destroy = 0
}

enum ZwpLinuxDmabufV1Request: UInt16, WireRequest {
  static let interface = "zwp_linux_dmabuf_v1"
  case destroy = 0
  case createParams = 1
  case getDefaultFeedback = 2
  case getSurfaceFeedback = 3
}

enum ZwpLinuxBufferParamsV1Request: UInt16, WireRequest {
  static let interface = "zwp_linux_buffer_params_v1"
  case destroy = 0
  case add = 1
  case create = 2
  case createImmed = 3
  case setSamplingDevice = 4
}

enum WlDisplayRequest: UInt16, WireRequest {
  static let interface = "wl_display"
  case sync = 0
  case getRegistry = 1
}

enum WlRegistryRequest: UInt16, WireRequest {
  static let interface = "wl_registry"
  case bind = 0
}
