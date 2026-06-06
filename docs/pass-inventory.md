# Render Pass Inventory

This document maps the legacy OpenGL passes to the frozen macOS Metal migration tasks.

## Summary

| Legacy Pass | Legacy File | Current OpenGL Role | Metal Target | Status |
|---|---|---|---|---|
| ConversionPass | `src/renderer/renderPasses/ConversionPass.cpp` | Mesh triangles to gaussian SSBO using VS/GS/FS, atomic counter, framebuffer, readback | `MetalConversionPass` + `shaders/metal/Conversion.metal` compute kernel | Implemented baseline, still needs regression tests |
| MeshRenderPass | `src/renderer/renderPasses/MeshRenderPass.cpp` | Mesh G-buffer/depth render with material textures | `MetalMeshRenderPass` + `shaders/metal/Mesh.metal` | Implemented baseline |
| GaussianSplattingPass | `src/renderer/renderPasses/GaussianSplattingPass.cpp` | Draw sorted gaussian quads via indirect draw and blending | `MetalGaussianRenderPass` + `shaders/metal/Gaussian.metal` | Implemented preview path |
| GaussiansPrepass | `src/renderer/renderPasses/GaussiansPrepass.cpp` | Compute culling/filtering, per-quad transforms, atomic count | Future Metal gaussian culling/filter pass | Deferred to stage 9 |
| RadixSortPass | `src/renderer/renderPasses/RadixSortPass.cpp` | Depth key compute, OpenGL radix sort, gather to sorted transform buffer | `MetalGaussianSortPass` + `shaders/metal/Sort.metal` | Implemented radix-style baseline, needs profiling |
| DepthPrepass | `src/renderer/renderPasses/DepthPrepass.cpp` | Mesh depth prepass into depth texture | Future Metal depth prepass/render target chain | Deferred to stage 9 |
| GaussianRelightingPass | `src/renderer/renderPasses/GaussianRelightingPass.cpp` | Deferred relighting, split screen, G-buffer composition | Future Metal PBR/debug composition pass | Deferred to stage 9 |
| GaussianShadowPass | `src/renderer/renderPasses/GaussianShadowPass.cpp` | Point light cubemap shadow, compute prepass, indirect draw | Future Metal shadow and relighting path | Deferred to stage 9 |

## Detailed Pass Notes

### ConversionPass

- Input: mesh vertex data, material factors, material textures, mesh bounds.
- Output: gaussian buffer, atomic gaussian count.
- OpenGL resources: VAO, SSBO, atomic counter buffer, framebuffer/renderbuffer.
- OpenGL state: blend enabled, depth disabled, cull disabled, `glFinish`, counter readback.
- Shaders: `converterVS.glsl`, `converterGS.glsl`, `converterFS.glsl`, `eigendecomposition.glsl`.
- Metal replacement: compute conversion kernel writes `device GaussianRecord*` and `device atomic_uint*`.
- Risk: high. Original geometry shader path cannot be represented directly in Metal.
- Frozen decision: use compute conversion as the native path. The procedural vertex approach remains a fallback design note, but current implementation has moved to compute for explicit resource control.

### MeshRenderPass

- Input: mesh vertices, material data, base color/normal/metallic-roughness textures, frame uniforms.
- Output: color/depth target.
- OpenGL resources: mesh VAO, textures, mesh G-buffer FBO.
- OpenGL state: depth test, cull face, no blending.
- Shaders: `meshRenderVS.glsl`, `meshRenderPS.glsl`.
- Metal replacement: `MetalMesh`, `MetalTexture`, `MetalMeshRenderPass`, `Mesh.metal`.
- Risk: medium. Current baseline does not yet restore all PBR/debug parity.

### GaussianSplattingPass

- Input: gaussian records, sorted indices/transforms, draw indirect buffer.
- Output: gaussian render target / drawable.
- OpenGL resources: quad VBO/EBO, per-quad transform buffer, indirect draw buffer.
- OpenGL state: additive/premultiplied blending, no depth write.
- Shaders: `gaussianSplattingVS.glsl`, `gaussianSplattingPS.glsl`, deferred variants.
- Metal replacement: instanced quad expansion from `GaussianRecord` and sorted indices in `Gaussian.metal`.
- Risk: medium-high. Needs visual regression against reference scenes.

### GaussiansPrepass

- Input: gaussian buffer, camera matrices, mesh depth texture.
- Output: filtered depth data, per-quad transforms, atomic count.
- OpenGL resources: SSBOs, atomic counter, optional depth texture.
- OpenGL state: compute dispatch and memory barriers.
- Shaders: `gaussianSplattingPrepassCS.glsl`.
- Metal replacement: future compute prepass.
- Risk: medium. Deferred until base gaussian loop is validated.

### RadixSortPass

- Input: gaussian count, depth buffer/key buffer/value buffer.
- Output: sorted values and sorted per-quad transforms.
- OpenGL resources: SSBOs, atomic counter readback, third-party radix sort helper.
- OpenGL state: compute dispatch, memory barriers, readback of valid count.
- Shaders: `radixSortPrepass.glsl`, `radixSortGather.glsl`, `thirdParty/RadixSort.hpp`.
- Metal replacement: `MetalGaussianSortPass` with depth key/count/prefix/reorder kernels.
- Risk: high. Sorting quality and occupancy require Metal capture profiling.

### DepthPrepass

- Input: mesh vertices and camera matrices.
- Output: mesh depth texture.
- OpenGL resources: depth FBO/texture.
- OpenGL state: depth test, clear color/depth.
- Shaders: `depthPrepassVS.glsl`, `depthPrepassPS.glsl`.
- Metal replacement: future depth-only render pass.
- Risk: medium.

### GaussianRelightingPass

- Input: gaussian/mesh G-buffer textures, shadow cubemap, point light state.
- Output: final composited color.
- OpenGL resources: fullscreen quad VAO/VBO/EBO, G-buffer textures, shadow cubemap.
- OpenGL state: stencil/scissor for split screen, framebuffer composition.
- Shaders: deferred gaussian/relighting shaders.
- Metal replacement: future composition pass and debug view mode pipeline.
- Risk: high due to many debug/PBR modes.

### GaussianShadowPass

- Input: gaussian buffer, light matrices, point light state.
- Output: shadow cubemap and per-face indirect draw data.
- OpenGL resources: cubemap depth texture, FBO, atomic counters, indirect draw buffer.
- OpenGL state: compute dispatch, memory barriers, depth cubemap render.
- Shaders: `gaussianPointShadowMappingCS.glsl`, `gaussianPointLightCubeMapShadowVS.glsl`, `gaussianPointLightCubeMapShadowPS.glsl`.
- Metal replacement: future shadow compute and cubemap render pass.
- Risk: high. Deferred until gaussian base rendering is stable.

## Stage 0 Acceptance

Every known legacy pass has a Metal target or an explicit deferred strategy. There are no pass-level unknowns left for the first migration loop.
