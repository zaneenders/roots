import Roots

extension DrawCommand {
  var rectangle: DrawRect {
    guard case .rectangle(let draw) = self else { fatalError("Expected a rectangle command") }
    return draw
  }
}

extension UIDrawBatch {
  var rectangles: [DrawRect] {
    var result: [DrawRect] = []
    for command in self { result.append(command.rectangle) }
    return result
  }
}
