# GPU Data Layout

This document freezes the CPU/MSL data layout strategy for the macOS Metal path.

## Layout Rules

- Prefer explicit scalar arrays in C++ core structs over API-specific vector types.
- Prefer `float4` slots for gaussian and constant-buffer ABI stability.
- Do not use `glm::vec3` or MSL `float3` across the CPU/GPU ABI boundary.
- All shared structs must have C++ `static_assert` checks for size and important offsets.
- MSL structs must mirror the documented slot order.
- Matrix convention is frozen as 16 contiguous floats in `Matrix4`.

## Current CPU Layout Sources

| Data | CPU Source | Notes |
|---|---|---|
| Mesh vertex | `src/core/MeshData.hpp::MeshVertex` | 17 floats; legacy mesh layout preserved |
| Mesh material CPU description | `src/core/MeshData.hpp::MeshMaterial` | CPU parser output; Metal has a compact copy |
| Metal mesh material | `src/renderer/metal/MetalMesh.hpp::MetalMeshMaterial` | GPU-facing material constant layout |
| Mesh draw range | `src/renderer/metal/MetalMesh.hpp::MetalMeshDrawRange` | 16-byte metadata record |
| Frame constants | `src/core/FrameData.hpp::FrameUniforms` | 16-byte aligned; used by mesh/gaussian/sort shaders |
| Gaussian record | `src/core/GaussianData.hpp::GaussianRecord` | Six `float4` slots, 96 bytes |
| Conversion params | `src/renderer/metal/MetalConversionPass.mm::MeshConversionParams` | 32 bytes |
| Sort params | `src/renderer/metal/MetalGaussianSortPass.mm` | 16-byte param blocks |

## Frozen Gaussian ABI

`GaussianRecord` uses six `float4` slots:

| Slot | Field | Meaning |
|---|---|---|
| 0 | `position` | xyz position, w reserved |
| 1 | `color` | rgba/albedo |
| 2 | `scale` | gaussian scale/radius data |
| 3 | `normal` | xyz normal, w reserved |
| 4 | `rotation` | quaternion/rotation data |
| 5 | `pbr` | metallic/roughness/extra flags |

C++ static assertions verify:

- Total size is `sizeof(float) * 4 * 6`.
- `color`, `scale`, `normal`, `rotation`, and `pbr` start at fixed `float4` slots.

## Mesh Vertex ABI

`MeshVertex` is frozen as 17 floats:

```text
position[3]
normal[3]
tangent[4]
uv[2]
normalizedUv[2]
scale[3]
```

MSL currently reads this as `const device float*` for compatibility with the packed legacy layout. If a typed MSL struct is introduced later, it must preserve the same byte order or migrate both CPU and shader code together.

## Frame Uniform ABI

`FrameUniforms` is 16-byte aligned and contains:

- model/view/projection/MVP matrices.
- camera position.
- focal/FOV values.
- viewport and reciprocal viewport.
- clipping planes.
- gaussian params.
- frame/render flags.

The struct must remain a constant-buffer-safe layout. Any added field must preserve 16-byte alignment.

## MSL Layout Notes

`shaders/metal/GpuTypes.metal` is intentionally a layout note file rather than a shared include right now. Runtime shader fallback concatenates all `.metal` files, so duplicating structs in a separate MSL file would create redefinition errors. When the shader build pipeline moves to true includes/metallib compilation, shared MSL types can be centralized.

## Stage 0 Acceptance

The data layout strategy is frozen, high-risk `float3` ABI traps are avoided, and C++ GPU-facing structs have static assertions or documented follow-up requirements.
