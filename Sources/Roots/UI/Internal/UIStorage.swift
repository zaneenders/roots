import Foundation
import Synchronization

private let ownerIDs = Atomic<UInt64>(1)

struct UIStorage: ~Copyable {
  let owner: UInt64
  var epoch: UInt64 = 0
  var nodes = UniqueArray<Node>()
  var keys: [UInt64: Int] = [:]
  var implicitKeys: [ImplicitNodeIdentity: Int] = [:]
  var identityPath: [ItemIdentity] = []
  var free = UniqueArray<Int>()
  var order = UniqueArray<Int>()
  var cursors = UniqueArray<Cursor>()
  var layouts: [LayoutElement] = []
  var backgrounds: [BackgroundRegion] = []
  var activeBackgrounds = 0
  var foregroundColor: Color?
  var selectionGroup: UInt64?
  var selectionGroupKeys: Set<UInt64> = []
  var groupSelection: GroupSelection?
  var focused: NodeHandle?
  var focusAfterLayout: NodeHandle?
  var focusToReveal: NodeHandle?
  var pressed: NodeHandle?
  var scrollTarget: NodeHandle?
  var scrollVelocity: Float = 0
  var scrollbarDrag: (handle: NodeHandle, grabOffset: Float)?
  let scrollAcceleration: Float
  let scrollDeceleration: Float
  var scrollInputTarget: NodeHandle?
  var scrollInputElapsed: Float = 1
  var scrollInputDelta: Float = 0
  var scrollInputMultiplier: Float = 1
  let drawCapacity: Int?
  var pendingScrollbars = UniqueArray<Int>()
  var draws = UniqueArray<DrawRect>()
  var pointerPosition: SIMD2<Float>?
  var droppedDraws = 0
  var needsAnimationFrame = false

  init(
    nodeCapacity: Int, drawCapacity: Int?, scrollAcceleration: Float = 0,
    scrollDeceleration: Float = 8
  ) {
    let id = ownerIDs.wrappingAdd(1, ordering: .relaxed).oldValue
    precondition(id != UInt64.max)
    owner = id
    nodes.reserveCapacity(nodeCapacity)
    keys.reserveCapacity(nodeCapacity)
    free.reserveCapacity(nodeCapacity)
    order.reserveCapacity(nodeCapacity)
    cursors.reserveCapacity(16)
    self.scrollAcceleration = scrollAcceleration
    self.scrollDeceleration = scrollDeceleration
    self.drawCapacity = drawCapacity
    draws.reserveCapacity(drawCapacity ?? 32_768)
  }

  func handle(_ index: Int) -> NodeHandle {
    NodeHandle(owner: owner, slot: index, generation: nodes[index].generation)
  }

  func resolve(_ handle: NodeHandle?) -> Int? {
    guard let handle, handle.owner == owner, handle.slot >= 0, handle.slot < nodes.count,
      nodes[handle.slot].live, nodes[handle.slot].generation == handle.generation
    else { return nil }
    return handle.slot
  }

}
