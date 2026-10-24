import Roots

private struct Forward<Content: Block>: Block {
  let content: Content
  init(@BlockBuilder content: () -> Content) { self.content = content() }
  var body: some Block { content }
}

@MainActor @BlockBuilder
func wide() -> some Block {
  Text("1")
  Text("2")
  Text("3")
  Text("4")
  Text("5")
  Text("6")
  Text("7")
  Text("8")
  Text("9")
  Text("10")
  Text("11")
  Text("12")
  Text("13")
  Text("14")
  Text("15")
  Text("16")
  Text("17")
  Text("18")
  Text("19")
  Text("20")
  Text("21")
  Text("22")
  Text("23")
  Text("24")
  Text("25")
  Text("26")
  Text("27")
  Text("28")
  Text("29")
  Text("30")
  Text("31")
  Text("32")
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
                          Text("Deep")
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
  Column(in: Region(0, 0, 100, 2000)) {
    wide()
    deep()
  }._build(into: &frame)
}
