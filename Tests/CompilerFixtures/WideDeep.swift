import Roots

private struct Forward<Content: Block>: Block {
  let content: Content
  init(@BlockBuilder content: () -> Content) { self.content = content() }
  var body: some Block { content }
}

@MainActor @BlockBuilder
func wide() -> some Block {
  LabelBlock(key: 1, "1")
  LabelBlock(key: 2, "2")
  LabelBlock(key: 3, "3")
  LabelBlock(key: 4, "4")
  LabelBlock(key: 5, "5")
  LabelBlock(key: 6, "6")
  LabelBlock(key: 7, "7")
  LabelBlock(key: 8, "8")
  LabelBlock(key: 9, "9")
  LabelBlock(key: 10, "10")
  LabelBlock(key: 11, "11")
  LabelBlock(key: 12, "12")
  LabelBlock(key: 13, "13")
  LabelBlock(key: 14, "14")
  LabelBlock(key: 15, "15")
  LabelBlock(key: 16, "16")
  LabelBlock(key: 17, "17")
  LabelBlock(key: 18, "18")
  LabelBlock(key: 19, "19")
  LabelBlock(key: 20, "20")
  LabelBlock(key: 21, "21")
  LabelBlock(key: 22, "22")
  LabelBlock(key: 23, "23")
  LabelBlock(key: 24, "24")
  LabelBlock(key: 25, "25")
  LabelBlock(key: 26, "26")
  LabelBlock(key: 27, "27")
  LabelBlock(key: 28, "28")
  LabelBlock(key: 29, "29")
  LabelBlock(key: 30, "30")
  LabelBlock(key: 31, "31")
  LabelBlock(key: 32, "32")
}

@MainActor func deep() -> some Block {
  Forward {
    Forward {
      Forward {
        Forward {
          Forward {
            Forward {
              Forward {
                Forward {
                  Forward {
                    Forward {
                      Forward {
                        Forward {
                          LabelBlock(key: 100, "Deep")
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

@MainActor func renderFixtures(into frame: inout UIFrame) {
  ColumnBlock(in: Rect(0, 0, 100, 2000)) {
    wide()
    deep()
  }._build(into: &frame)
}
