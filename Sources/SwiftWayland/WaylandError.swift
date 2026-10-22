public enum WaylandError: Error, Equatable {
  case invalidConfiguration
  case connection
  case missingGlobals
  case busy
  case dispatch
}
