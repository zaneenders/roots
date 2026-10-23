import Roots
import RootsDesktop

@main
struct MarkdownDemoApp: RootsApp {
  var window: some Window {
    DesktopWindow("Markdown · Roots", size: .init(940, 1080)) { viewport in
      MarkdownPage(bounds: viewport.bounds)
    }
  }
}
