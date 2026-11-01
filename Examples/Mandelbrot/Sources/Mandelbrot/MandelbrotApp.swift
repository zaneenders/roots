import Roots
import RootsDesktop

@main
struct MandelbrotApp: RootsApp {
  var window: some Window {
    DesktopWindow(
      "Mandelbrot · Roots", width: 1120, height: 840, drawCapacity: MandelbrotImage.drawCapacity
    ) { viewport in
      MandelbrotPage(bounds: viewport.bounds)
    }
  }
}
