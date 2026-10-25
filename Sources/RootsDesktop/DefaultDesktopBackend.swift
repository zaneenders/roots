import Roots

#if os(macOS)
import MacOSBridge
#elseif os(Linux)
import WaylandBridge
#endif

extension DesktopSystem {
  /// Supply a backend explicitly on platforms without a bundled implementation.
  public static let defaultBackend: (any DesktopBackend)? = {
    #if os(macOS)
    MacOSBackend()
    #elseif os(Linux)
    WaylandBackend()
    #else
    nil
    #endif
  }()
}
