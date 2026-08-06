# Metal Gaussian Sort Notes

Scope: `MetalGaussianSortBuffer.*`, `MetalGaussianSortPass.*`,
`MetalSortPlanner.hpp`, `MetalGaussianRenderPass.*`, and `shaders/metal/Sort.metal`.

## Current Implementation

- Depth keys are generated in `gaussianDepthKeyKernel` from the current view
  matrix. Positive view depth is converted to a descending sortable `uint` key,
  and the index buffer starts as identity indices.
- `MetalGaussianSortBuffer` owns primary key/index buffers, scratch key/index
  buffers, radix block counts, and global offsets. Capacity is capped to
  `uint32_t` because shader item counts and indices are `uint`.
- The radix sort is fixed at 8 passes, 4 bits per pass, 16 bins, and 256 items
  per count/reorder threadgroup. Block-count storage is
  `ceil(capacity / 256) * 16 * sizeof(uint32_t)`.
- The even 8-pass ping-pong returns sorted keys/indices to the primary buffers.
  `MetalGaussianRenderPass` reads the sorted index buffer from
  `MetalGaussianSortBuffer`.
- `MetalRenderer` re-sorts when gaussian count changes or the view matrix
  changes. Failed sort encodes are recorded through
  `MetalGaussianSortPass::lastDiagnostic()`.
- `resourceStats()` reports capacity, active count, per-buffer byte counts, and
  total bytes for renderer/pass diagnostics.

## Next Integration Points

- Replace hard-coded sort constants in `MetalGaussianSortPass` with
  `MetalSortPlanner` values, or delete planner-only paths if the constants are
  intentionally frozen.
- Add a GPU readback validation test with a tiny fixed gaussian set and known
  camera depth order. The current checks prove buffer sizing and encode
  contracts, not sorted data correctness.
- Surface sort resource stats in the resource telemetry path so memory growth is
  visible when conversion output increases.
- Profile prefix/reorder cost before changing radix width. The current prefix
  kernel scans every block per radix bin on one 16-thread dispatch.

## Risks And Checks

- `Sort.metal` and `MetalGaussianSortPass.mm` duplicate parameter structs. The
  static asserts cover CPU size only; field order must stay manually aligned
  with the shader.
- Any change to radix pass count can leave final indices in scratch buffers.
  Keep the render pass source buffer and ping-pong plan in sync.
- Capacity growth recreates all sort buffers. Large scene conversion can cause
  allocation churn unless conversion reserves near the final gaussian count.
- Shader-side saturating adds avoid overflow writes but can hide incorrect
  counts. Validation should check sorted index count and monotonic depth keys.
