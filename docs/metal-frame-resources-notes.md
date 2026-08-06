# Metal Frame Resources Notes

Scope: `MetalFrameResources.*`, `MetalFrameUniformBuffer.*`, and the current
renderer frame lifecycle in `MetalRenderer.mm`.

## Current Implementation

- `MetalFrameResources` is a CPU-side ring-frame ledger. It tracks current frame
  index, frame number, per-frame dynamic offsets, allocation records,
  high-water marks, submitted/completed state, and reuse warnings.
- It does not own Metal buffers yet. `allocateDynamic()` only records aligned
  suballocation metadata and grows the recorded dynamic capacity when needed.
- `MetalRenderer` calls `beginFrame()` before encoding, marks the frame
  submitted after command buffer commit, and marks it completed from the command
  buffer completion handler.
- `MetalFrameUniformBuffer` still owns one shared Metal buffer per ring frame.
  `frameBinding()` normalizes requested frame indices, reports wrap state,
  upload/submission/completion serials, and always returns offset `0`.
- Uniform layout helpers are centralized: `uniformSize()`,
  `uniformAlignment()`, `alignedUniformSize()`, and `frameStride()` describe the
  current `FrameUniforms` upload shape.

## Next Integration Points

- Add the actual Metal dynamic-ring buffer owner behind
  `MetalFrameResources::Allocation`; keep the existing allocation metadata as
  diagnostics and capacity accounting.
- Move small per-frame data first: pass constants, debug counters, and then
  `FrameUniforms`. Existing `frameBinding()` should remain the pass-facing API
  while offsets become non-zero.
- Thread allocator byte ranges into pass encode diagnostics so a capture can
  show frame index, normalized ring index, buffer, offset, size, and alignment.
- Decide whether the existing frame semaphore remains the only in-flight guard
  once multiple transient buffers share the same ring allocator.

## Risks And Checks

- `beginFrame()` can skip submitted slots, but if all slots are submitted it
  falls back to the preferred slot and records a reuse warning. The allocator
  path must preserve this warning before writing into shared transient memory.
- Dedicated uniform buffers currently hide offset mistakes because every binding
  uses offset `0`. Suballocation rollout should add assertions for alignment and
  `offset + size <= bufferSize`.
- `MetalFrameUniformBuffer` counts overwritten in-flight uploads. That signal
  should either stay visible after migration or be replaced by equivalent ring
  allocator diagnostics.
