import Foundation
import PackagePlugin

@main
struct ShaderSourcePlugin: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
    let shaders = target.directoryURL.appendingPathComponent("Shaders")
    let generator = try context.tool(named: "ShaderSourceGenerator")
    return ["Rectangle", "Polyline"].map { name in
      let vertex = shaders.appendingPathComponent(name + ".vert")
      let fragment = shaders.appendingPathComponent(name + ".frag")
      let type = name == "Rectangle" ? "NativeShaders" : "PolylineShaders"
      let output = context.pluginWorkDirectoryURL.appendingPathComponent(type + ".swift")
      return .buildCommand(
        displayName: "Embed \(name) shaders", executable: generator.url,
        arguments: [vertex.path, fragment.path, output.path, type],
        inputFiles: [vertex, fragment], outputFiles: [output])
    }
  }
}
