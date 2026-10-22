import Testing

@testable import ShaderSourceGenerator

@Test func generatedShaderSourceEscapesSwiftSyntax() {
  let source = ShaderSourceGenerator.swiftSource(
    vertex: "// \"quoted\" \\(notInterpolation)\n\t\\\r\n",
    fragment: "// café 🎨\n")
  #expect(
    source.contains(#"static let vertexSource = "// \"quoted\" \\(notInterpolation)\n\t\\\r\n""#))
  #expect(source.contains(#"static let fragmentSource = "// café 🎨\n""#))
  #expect(source.hasSuffix("}\n"))
}

@Test func generatedShaderSourceSupportsEmptyFilesAndIsDeterministic() {
  let source = ShaderSourceGenerator.swiftSource(vertex: "", fragment: "")
  #expect(source.hasPrefix("enum NativeShaders {\n"))
  #expect(source.contains(#"static let vertexSource = """#))
  #expect(source.contains(#"static let fragmentSource = """#))
  #expect(source == ShaderSourceGenerator.swiftSource(vertex: "", fragment: ""))
}
