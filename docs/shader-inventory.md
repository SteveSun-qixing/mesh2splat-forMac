# Shader Inventory

This document freezes the shader migration map from legacy GLSL to Metal Shading Language.

## Current Metal Shader Files

| MSL File | Purpose |
|---|---|
| `shaders/metal/Clear.metal` | Clear/fullscreen placeholder shader |
| `shaders/metal/Mesh.metal` | Mesh vertex/fragment rendering |
| `shaders/metal/Conversion.metal` | Mesh-to-gaussian compute conversion |
| `shaders/metal/Gaussian.metal` | Gaussian preview instanced rendering |
| `shaders/metal/Sort.metal` | Gaussian depth key and radix-style sort kernels |
| `shaders/metal/GpuTypes.metal` | Layout freeze notes; intentionally no duplicate struct definitions |

## Conversion Shaders

| GLSL Shader | Type | Key Features | Metal Target / Strategy | Risk |
|---|---|---|---|---|
| `src/shaders/conversion/converterVS.glsl` | Vertex | Reads mesh vertices, passes attributes to GS/FS | Superseded by `Conversion.metal` compute input decoding | Medium |
| `src/shaders/conversion/converterGS.glsl` | Geometry | Triangle-level conversion logic; no direct Metal equivalent | Frozen strategy: native compute conversion in `meshVertexConversionKernel`. Procedural vertex reconstruction remains fallback design if compute path regresses | High |
| `src/shaders/conversion/converterFS.glsl` | Fragment | Samples material textures and appends gaussian data | Folded into `Conversion.metal` compute kernel with explicit texture bindings | High |
| `src/shaders/conversion/eigendecomposition.glsl` | Common | Math helper for covariance/rotation style logic | Port relevant math into MSL helper functions as needed | Medium |

## Rendering Shaders

| GLSL Shader | Type | Key Features | Metal Target / Strategy | Risk |
|---|---|---|---|---|
| `src/shaders/rendering/meshRenderVS.glsl` | Vertex | Mesh transform and varying setup | `Mesh.metal::meshVertex` | Medium |
| `src/shaders/rendering/meshRenderPS.glsl` | Fragment | Base color/normal/metallic material sampling | `Mesh.metal::meshFragment`, PBR parity still pending | Medium |
| `src/shaders/rendering/gaussianSplattingVS.glsl` | Vertex | Quad expansion from sorted transform data | `Gaussian.metal::gaussianPreviewVertex` | Medium |
| `src/shaders/rendering/gaussianSplattingPS.glsl` | Fragment | Gaussian alpha/color accumulation | `Gaussian.metal::gaussianPreviewFragment` | Medium |
| `src/shaders/rendering/gaussianSplattingDeferredVS.glsl` | Vertex | Deferred gaussian path | Future advanced gaussian/debug pass | High |
| `src/shaders/rendering/gaussianSplattingDeferredPS.glsl` | Fragment | Deferred G-buffer material output | Future advanced gaussian/debug pass | High |
| `src/shaders/rendering/gaussianSplattingPrepassCS.glsl` | Compute | Culling/filtering and per-quad transform generation | Future Metal compute prepass | Medium |
| `src/shaders/rendering/radixSortPrepass.glsl` | Compute | Depth key/value generation | `Sort.metal::gaussianDepthKeyKernel` | Medium |
| `src/shaders/rendering/radixSortGather.glsl` | Compute | Gather sorted transform output | `Sort.metal::gaussianRadixReorderKernel` plus render-time indexed fetch | Medium |
| `src/shaders/rendering/frameBufferReaderCS.glsl` | Compute | Read framebuffer data | Future export/debug readback path | Low |
| `src/shaders/rendering/depthPrepassVS.glsl` | Vertex | Mesh depth prepass | Future Metal depth-only pass | Medium |
| `src/shaders/rendering/depthPrepassPS.glsl` | Fragment | Depth prepass fragment | Future Metal depth-only pass | Medium |
| `src/shaders/rendering/gaussianPointShadowMappingCS.glsl` | Compute | Shadow cubemap prepass data | Future Metal shadow compute | High |
| `src/shaders/rendering/gaussianPointLightCubeMapShadowVS.glsl` | Vertex | Cubemap shadow draw | Future Metal cubemap shadow pipeline | High |
| `src/shaders/rendering/gaussianPointLightCubeMapShadowPS.glsl` | Fragment | Cubemap shadow fragment | Future Metal cubemap shadow pipeline | High |
| `src/shaders/rendering/common.glsl` | Common | Shared math/constants | Port selectively into MSL helpers | Medium |

## Third-Party Generated GLSL

| Source | Role | Metal Strategy |
|---|---|---|
| `thirdParty/RadixSort.hpp` | OpenGL compute radix sort helper | Replaced by `MetalGaussianSortPass`; improve scan/reorder in stage 8 profiling |

## Migration Rules

- No new macOS runtime feature may depend on GLSL.
- New macOS shaders must live under `shaders/metal`.
- MSL function names must be represented in `MetalPipelineCache` descriptors.
- Pipeline creation errors must include function name and pipeline label.
- Runtime shader source fallback remains required until the local Metal Toolchain component is installed.

## Stage 0 Acceptance

Every GLSL shader has a current Metal target or a deferred strategy. Geometry shader usage is explicitly accounted for and is not a hidden unknown.
