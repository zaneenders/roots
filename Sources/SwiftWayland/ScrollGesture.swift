struct ScrollGesture {
  var source: UInt32?
  var distance: Float = 0
  var time: UInt32?
  var stopTime: UInt32?
  private var lastSource: UInt32?
  private var lastTime: UInt32?
  private var velocity: Float = 0

  mutating func finish() -> Float? {
    defer {
      source = nil
      distance = 0
      time = nil
      stopTime = nil
    }
    if let time, distance != 0 || stopTime == nil {
      if source != lastSource {
        lastTime = nil
        velocity = 0
      }
      lastSource = source
      if source == WaylandPointerAxisSource.finger.rawValue, let previous = lastTime {
        let elapsed = time &- previous
        if elapsed > 0 && elapsed <= 100 {
          let sample = min(8_000, max(-8_000, distance * 1_000 / Float(elapsed)))
          velocity = velocity * sample <= 0 ? sample : (velocity + sample) * 0.5
        } else if elapsed > 100 {
          velocity = 0
        }
      } else {
        velocity = 0
      }
      lastTime = time
    }
    guard let stopTime else { return nil }
    let release: Float
    if (source ?? lastSource) == WaylandPointerAxisSource.finger.rawValue,
      let lastTime, stopTime &- lastTime <= 100
    {
      release = velocity
    } else {
      release = 0
    }
    lastSource = nil
    lastTime = nil
    velocity = 0
    return release
  }
}
