import Foundation
import PackagePlugin

@main
struct FontAtlasPlugin: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
    let generator = try context.tool(named: "FontAtlasGenerator")
    let emojiGenerator = try context.tool(named: "EmojiAtlasGenerator")
    let package = context.package.directoryURL.appending(path: "Vendor")
    let font = package.appending(path: "fonts/NotoSansMono-Regular.ttf")
    let sequences = package.appending(path: "fonts/EmojiSequences.txt")
    let emojiFont = package.appending(path: "fonts/NotoColorEmoji.ttf")
    let coverage = package.appending(path: "AtlasCoverage.txt")
    let output = context.pluginWorkDirectoryURL.appending(path: "FontAtlas.atlas")
    let emojiOutput = context.pluginWorkDirectoryURL.appending(path: "EmojiAtlas.atlas")
    return [
      .buildCommand(
        displayName: "Generating FontAtlas.atlas",
        executable: generator.url,
        arguments: [font.path, coverage.path, output.path],
        inputFiles: [font, coverage],
        outputFiles: [output]),
      .buildCommand(
        displayName: "Generating EmojiAtlas.atlas",
        executable: emojiGenerator.url,
        arguments: [emojiFont.path, sequences.path, emojiOutput.path],
        inputFiles: [emojiFont, sequences],
        outputFiles: [emojiOutput])
    ]
  }
}
