extension Keyboard {
  struct Repeat {
    let key: UInt32
    var next: ContinuousClock.Instant
  }
}
