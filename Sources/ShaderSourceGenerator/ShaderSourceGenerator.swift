import Foundation

@main
struct ShaderSourceGenerator {
  static func main() throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 4 || arguments.count == 5 else { throw GeneratorError.usage }
    let vertex = try String(contentsOf: URL(fileURLWithPath: arguments[1]), encoding: .utf8)
    let fragment = try String(contentsOf: URL(fileURLWithPath: arguments[2]), encoding: .utf8)
    try swiftSource(
      vertex: vertex, fragment: fragment,
      name: arguments.count == 5 ? arguments[4] : "NativeShaders"
    )
    .write(
      to: URL(fileURLWithPath: arguments[3]), atomically: true, encoding: .utf8)
  }

  static func swiftSource(vertex: String, fragment: String, name: String = "NativeShaders")
    -> String
  {
    return """
      enum \(name) {
        static let vertexSource = \(String(reflecting: vertex))
        static let fragmentSource = \(String(reflecting: fragment))
      }

      """
  }
}

private enum GeneratorError: Error, CustomStringConvertible {
  case usage

  var description: String {
    "Usage: ShaderSourceGenerator <vertex shader> <fragment shader> <output.swift>"
  }
}
