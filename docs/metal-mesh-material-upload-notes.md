# Metal Mesh Material Upload Notes

Scope: `MetalMesh.*`, `MetalSceneResources.*`, and the mesh/conversion passes
that consume uploaded material state.

## Current Implementation

- `MetalMesh` uploads vertices, sequential indices, draw ranges, and compact
  `MetalMeshMaterial` records into private Metal buffers through
  `MetalResourceUploadBatch`.
- Empty material lists are replaced with one default material. Draw ranges whose
  material index is out of range are clamped to material `0` and counted in
  upload diagnostics.
- Each mesh owns five texture arrays: base color, metallic-roughness, normal,
  occlusion, and emissive. Slot `0` in each array is a per-mesh fallback texture.
- Missing texture references, out-of-range image indices, malformed RGBA8 image
  data, and failed texture uploads resolve to fallback slot `0`.
- Texture uploads require `width > 0`, `height > 0`, `channels == 4`, and
  `rgba8.size() == width * height * 4` before creating the Metal texture.
- Real textures are cached by image index per texture class during one mesh
  upload, so repeated references share the uploaded `MetalTexture` within that
  mesh.
- `MetalSceneResources` aggregates mesh counts, texture counts, resource byte
  totals through `sizeBytes()`, skipped empty meshes, failed mesh index/status,
  and upload diagnostics.

## Next Integration Points

- Feed `MetalSceneResources::uploadDiagnostics()` into the SwiftUI/renderer
  diagnostics panel so fallback-heavy assets are visible during load.
- Decide whether fallback textures should remain per mesh or move to a shared
  renderer-level cache. Current local ownership is simple but duplicates five
  1x1 textures per mesh.
- Extend upload diagnostics with final material/texture table summaries if
  conversion failures need to identify the exact mesh/range/material slot.
- Add a load smoke case for mixed valid, missing, shared, and invalid material
  textures so fallback counts stay stable.

## Risks And Checks

- Mesh render and conversion passes still fail if a material texture accessor
  returns nil. Fallback slot `0` should make that rare; nil means the upload
  invariants were broken.
- Default emissive currently uses a white 1x1 texture. Verify shader factor
  handling before treating this as physically neutral for all materials.
- Texture caches are per texture class. The same source image used as base color
  and emissive uploads twice, which is correct for current formats but affects
  memory accounting.
- `MetalMesh` only uploads triangle-list ranges. Future indexed mesh support
  needs different draw range validation and conversion capacity math.
