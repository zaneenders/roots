public enum MacOSWindowError: Error, Equatable {
  case invalidConfiguration
  case alreadyRunning
  case deviceUnavailable
  case resourceAllocation
  case missingShader
  case rendering(String)
}
