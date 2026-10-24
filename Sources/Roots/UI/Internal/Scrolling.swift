import Foundation

extension UIStorage {
  mutating func layoutScrolls() {
    for i in order {
      nodes[i].region = nodes[i].layoutRegion
      if let parent = nodes[i].scrollParent {
        let container = nodes[parent]
        nodes[i].scrollTranslation = container.scrollTranslation + container.scrollOffset
        nodes[i].clip = container.clip.map { $0.intersection(container.region) } ?? container.region
        nodes[i].region.y -= nodes[i].scrollTranslation
      } else {
        nodes[i].scrollTranslation = 0
        nodes[i].clip = nil
      }
    }
  }

  mutating func setScrollOffset(_ offset: Float, for i: Int) {
    let limit = max(0, nodes[i].contentHeight - nodes[i].region.height)
    let clamped = min(limit, max(0, offset))
    nodes[i].scrollOffset = clamped
    if scrollTarget == handle(i),
      clamped != offset || (clamped == 0 && scrollVelocity < 0)
        || (clamped == limit && scrollVelocity > 0)
    {
      scrollVelocity = 0
    }
  }

  mutating func reveal(_ i: Int, padding: Float = 0) {
    let node = nodes[i].region
    var region = Region(
      node.x - padding, node.y - padding, node.width + 2 * padding, node.height + 2 * padding)
    var parent = nodes[i].scrollParent
    while let p = parent {
      let viewport = nodes[p].region
      let top = region.y - viewport.y
      let bottom = region.y + region.height - viewport.y - viewport.height
      let delta: Float
      if top < 0 && bottom < 0 {
        delta = max(top, bottom)
      } else if top > 0 && bottom > 0 {
        delta = min(top, bottom)
      } else {
        delta = 0
      }
      let previousOffset = nodes[p].scrollOffset
      setScrollOffset(previousOffset + delta, for: p)
      region.y -= nodes[p].scrollOffset - previousOffset
      layoutScrolls()
      region = region.intersection(viewport)
      parent = nodes[p].scrollParent
    }
  }

  func scrollbar(at i: Int) -> VerticalScrollbar? {
    let node = nodes[i]
    guard node.scrollable, node.showsScrollIndicator else { return nil }
    return VerticalScrollbar(
      viewport: node.region, contentHeight: node.contentHeight, offset: node.scrollOffset)
  }

  mutating func updateScrolls(
    input: Input, dt: Float, keyboardInput: Bool, inputElapsed: Float? = nil
  ) {
    let elapsed = inputElapsed ?? dt
    if elapsed.isFinite, elapsed > 0 { scrollInputElapsed = min(1, scrollInputElapsed + elapsed) }
    if input.pressed || keyboardInput { scrollInputTarget = nil }
    if let i = resolve(scrollTarget), nodes[i].scrollable {
      if input.pressed || keyboardInput { scrollTarget = nil }
    } else {
      scrollTarget = nil
    }
    if scrollTarget == nil { scrollVelocity = 0 }
    for position in 0..<order.count {
      let i = order[position]
      if nodes[i].scrollable { setScrollOffset(nodes[i].scrollOffset, for: i) }
    }
    layoutScrolls()
    if let drag = scrollbarDrag {
      if let i = resolve(drag.handle), scrollbar(at: i) != nil {
        scrollTarget = nil
        scrollVelocity = 0
      } else {
        scrollbarDrag = nil
      }
    }
    if input.pressed { scrollbarDrag = nil }
    if let i = resolve(focusToReveal), nodes[i].isFocusable { reveal(i, padding: 2) }
    focusToReveal = nil
    let scrolling =
      scrollbarDrag == nil && input.mousePosition != nil && input.scrollY.isFinite && input.scrollY != 0
    if scrolling, let position = input.mousePosition {
      scrollVelocity = 0
      scrollTarget = nil
      let hit = hitTest(at: position, scrollable: true)
      var target = hit.scrollbar ?? hit.node
      while let i = target, !nodes[i].scrollable && nodes[i].interaction.onScroll == nil {
        target = nodes[i].scrollParent
      }
      if let i = target {
        if scrollInputTarget == handle(i), (input.scrollY > 0) == (scrollInputDelta > 0),
          scrollInputElapsed > 0, scrollInputElapsed <= 0.15
        {
          scrollInputMultiplier =
            1 + min(2, scrollAcceleration * abs(input.scrollY) / scrollInputElapsed / 600)
        } else {
          scrollInputMultiplier = 1
        }
        scrollInputTarget = handle(i)
        scrollInputDelta = input.scrollY
        scrollInputElapsed = 0
        let distance = min(
          Float.greatestFiniteMagnitude,
          max(-Float.greatestFiniteMagnitude, input.scrollY * scrollInputMultiplier))
        if let onScroll = nodes[i].interaction.onScroll {
          let region = nodes[i].region
          onScroll(
            ScrollEvent(
              deltaY: distance, position: Coordinate(x: position.x - region.x, y: position.y - region.y),
              region: region))
        } else {
          scrollTarget = handle(i)
          setScrollOffset(nodes[i].scrollOffset + distance, for: i)
          layoutScrolls()
        }
      } else {
        scrollInputTarget = nil
      }
    }
    if scrollbarDrag == nil, !input.pressed && !keyboardInput,
      let velocity = input.scrollVelocityY, velocity.isFinite, let i = resolve(scrollTarget)
    {
      let scaledVelocity = velocity * scrollInputMultiplier
      scrollVelocity = abs(scaledVelocity) < 5 ? 0 : min(8_000, max(-8_000, scaledVelocity))
      setScrollOffset(nodes[i].scrollOffset, for: i)
    } else if !scrolling,
      scrollVelocity != 0, dt.isFinite && dt > 0, let i = resolve(scrollTarget)
    {
      let decay = exp(-scrollDeceleration * dt)
      let remaining = scrollVelocity * decay
      let settled = abs(remaining) < 5
      let distance =
        settled
        ? (scrollVelocity - (scrollVelocity > 0 ? 5 : -5)) / scrollDeceleration
        : scrollVelocity * (-expm1(-scrollDeceleration * dt) / scrollDeceleration)
      scrollVelocity = settled ? 0 : remaining
      setScrollOffset(nodes[i].scrollOffset + distance, for: i)
      layoutScrolls()
    }
    if input.scrollVelocityY != nil { scrollInputTarget = nil }
    if let position = input.mousePosition, let i = resolve(pressed), !input.pressed, !input.released,
      let parent = nodes[i].scrollParent,
      dt.isFinite, dt > 0, nodes[i].textLayout != nil
    {
      let viewport = nodes[i].clip ?? nodes[parent].region
      let distance =
        position.y < viewport.y
        ? position.y - viewport.y
        : max(0, position.y - viewport.y - viewport.height)
      if distance.isFinite, distance != 0 {
        let previous = nodes[parent].scrollOffset
        setScrollOffset(previous + max(-600, min(600, distance * 10)) * min(dt, 0.1), for: parent)
        if nodes[parent].scrollOffset != previous { needsAnimationFrame = true }
        layoutScrolls()
      }
    }
  }
}
