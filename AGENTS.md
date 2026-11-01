## TigerStyle

Across the repository, follow [TigerStyle](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md)'s priorities: safety, predictable performance, then developer experience.

- Bound queues, retries, task fan-out, buffer growth, and work per frame/batch. Define what happens at capacity.
- Allocate bounded subsystem storage during initialization, then reuse it during steady-state processing without heap allocation or capacity growth. Calculate memory budgets from maximum workload sizes and concurrency. Define capacity-exhaustion behavior, document the scope of the guarantee and any exceptions, and verify allocation behavior under maximum load and exhaustion paths.
- Handle expected failures explicitly; enforce internal invariants with types and appropriate assertions/preconditions. Recheck shared-state assumptions across `await`.
- Keep control flow and mutation explicit. Use precise names, include units where relevant, and document why.
- Estimate costs before coding; reuse buffers and batch hot-path work within latency budgets. Verify gains with [paired profiling](apps/shape-tree-desktop/performance/profiling.md) and output-correctness checks.
- Test changed behavior at boundaries and failure paths. Keep changes focused and justify new dependencies.

## Swift 6.4

Prefer [Swift 6.4](https://www.swift.org/blog/swift-6.4-released/) ownership, lifetime, and storage APIs when they fit the workload. Check public API availability against the pinned toolchain and deployment targets before adoption.

| Workload | Prefer |
| --- | --- |
| Single-owner state and resources | `struct: ~Copyable`; `consuming` / `consume` for ownership transfer |
| A uniquely owned heap value | `UniqueBox<T>` when heap indirection is required |
| Uniquely owned, growable buffers | `UniqueArray<T>`; restrict growth to initialization or explicitly budgeted allocation paths |
| Startup-allocated buffers and queues | `RigidArray<T>` / `RigidDeque<T>` from Swift Collections; keep capacity fixed during steady-state processing |
| Fixed-size inline storage / vector math | `InlineArray`; `SIMD` where its layout and arithmetic semantics fit |
| Scoped scratch storage where allocation is permitted | `withTemporaryAllocation` with a bounded element or byte count; it may use heap storage |
| Access without ownership transfer | `borrowing` / `inout`; `borrow` / `mutate` accessors to expose storage without copying |
| Stored, lifetime-bound access to one value | `Ref<T>` for read access; `MutableRef<T>` for exclusive mutation |
| Borrowed contiguous storage | `Span<T>` / `MutableSpan<T>`; `RawSpan` / `MutableRawSpan` for bytes |
| Incremental buffer initialization | `OutputSpan<T>` / `OutputRawSpan` to track initialized contents |
| Iteration without copying elements | `Iterable` and borrowing iteration where supported |
| Owner-bound views | `~Escapable` with lifetime dependencies tied to the actual owner |

- Never use `@unchecked Sendable`. Prefer compiler-checked isolation; use `Synchronization.Mutex` when shared mutable state requires synchronous locking and platform support permits.
- Frame-scoped borrows must not escape into retained closures/tasks or cross `await`. Use the pinned compiler's lifetime annotations and check the required `Lifetimes` feature settings for custom owner-bound views; justify new experimental features. Keep unsafe C/GPU interop narrowly scoped.
- Keep reusable buffers and pools in long-lived owners; expose borrowed views and bounded operations instead of capacity-changing APIs. Audit stored values and called code for hidden allocations, including strings, nested collections, CoW copies, escaping closures, and task creation. Reset counts or cursors while retaining storage, and wait for borrowers or GPU work to finish before reuse.
- Use [Swift Collections](https://github.com/apple/swift-collections) for `RigidArray<T>` when explicit capacity control is needed, `UniqueDeque` / `RigidDeque` for queues, `BitSet` / `BitArray` for dense flags, and `OrderedDictionary` / `OrderedSet` / `Heap` for ordering or priority semantics. Check the pinned package API, product, and required traits. Handle capacity exhaustion before insertion; rigid containers may trap when full. Justify new dependencies.
- `~Copyable` does not remove ARC from stored reference values, and unique ownership does not eliminate heap allocation or growth costs. Retain classes and CoW collections when shared identity or snapshots are required. Make targeted changes and verify ARC, allocation, and latency effects with paired profiling and output-correctness checks for the affected workload; use the linked desktop workflow for rendering changes.

## Swift Packages 

The following are pre approved switch packages we can leverage as needed

- https://github.com/apple/swift-algorithms
- https://github.com/apple/swift-nio
- https://github.com/apple/swift-collections
- https://github.com/swiftlang/swift-subprocess
