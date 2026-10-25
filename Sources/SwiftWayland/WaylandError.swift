public enum WaylandError: Error, Equatable {
  case invalidConfiguration
  case connection
  case missingGlobals
  case busy
  case dispatch
  case protocolViolation(WaylandProtocolError)
}

public struct WaylandProtocolError: Error, Equatable, Sendable, CustomStringConvertible {
  public let objectID: UInt32
  public let interface: String?
  public let code: UInt32
  public let message: String

  public init(objectID: UInt32, interface: String?, code: UInt32, message: String) {
    self.objectID = objectID
    self.interface = interface
    self.code = code
    self.message = message
  }

  public var description: String {
    "\(interface ?? "unknown")@\(objectID): error \(code): \(message)"
  }
}
