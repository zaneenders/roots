@MainActor
@resultBuilder
public enum ParagraphBuilder {
  public static func buildExpression(_ text: Text) -> [Text] { [text] }
  public static func buildExpression(_ background: _Background<Text>) -> [Text] {
    [background.content.withInlineBackground(background.color)]
  }
  public static func buildBlock() -> [Text] { [] }
  public static func buildPartialBlock(first: [Text]) -> [Text] { first }
  public static func buildPartialBlock(accumulated: [Text], next: [Text]) -> [Text] {
    accumulated + next
  }
  public static func buildOptional(_ content: [Text]?) -> [Text] { content ?? [] }
  public static func buildEither(first: [Text]) -> [Text] { first }
  public static func buildEither(second: [Text]) -> [Text] { second }
  public static func buildArray(_ content: [[Text]]) -> [Text] { content.flatMap { $0 } }
}
