import Roots

struct MandelbrotPage: Block {
  let bounds: Region

  var body: some Block {
    Stack(in: bounds) {
      Column(gap: 16) {
        Text("Mandelbrot")
          .size(32)
        Text("640 × 400  /  160 iterations  /  z → z² + c")
          .size(14)
          .color(Color(0.47, 0.57, 0.69))
        Canvas(key: 1, color: Color(0.035, 0.05, 0.08)) { context in
          MandelbrotImage.paint(in: &context)
        }
        .frame(width: .fill, height: .fill)
      }
      .padding(24)
      .frame(width: .fill, height: .fill)
    }
    .background(Color(0.06, 0.08, 0.12))
  }
}
