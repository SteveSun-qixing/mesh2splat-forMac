# Target Architecture

This document freezes the target architecture and directory boundaries for the native macOS Metal version.

## Target Layers

```text
src/
  app/
    macos/              # AppKit, MTKView, macOS input, file dialogs
  core/                 # API-neutral data, math, camera, parsing outputs
  io/                   # Future API-neutral import/export boundary
  renderer/
    metal/              # Metal resources, passes, pipelines, command scheduling
shaders/
  metal/                # MSL source and layout notes
docs/                   # Migration and verification docs
tests/                  # Future unit/regression tests
```

## Current Directory Mapping

| Area | Current Files | Rule |
|---|---|---|
| macOS app shell | `src/app/macos/MacApp.mm`, `MetalView.mm`, `MetalView.hpp` | May import AppKit/MetalKit. Must not own core algorithms |
| Core data/camera | `src/core/*.hpp`, `src/core/*.cpp` | Must not import OpenGL, GLFW, AppKit, Metal, or MetalKit |
| Metal backend | `src/renderer/metal/*` | May use Objective-C++ and Metal. Owns GPU resources |
| Legacy OpenGL backend | `src/renderer/renderPasses/*`, old renderer files | Historical reference only for macOS migration |
| MSL shaders | `shaders/metal/*.metal` | Only native macOS shader source |

## Backend Boundary

The AppKit layer calls the C++ `MetalRenderer` through a narrow interface:

- `initialize`
- `resize`
- `loadMeshFile`
- view/visualization/scale/sample settings
- `draw`
- stats and diagnostics access

The AppKit layer does not create mesh buffers, textures, pipelines, or shader libraries directly.

## Resource Ownership

| Resource | Owner |
|---|---|
| `id<MTLDevice>` and command queue | `MetalDeviceContext` |
| Command buffers | `MetalCommandScheduler` or scoped upload batches |
| Static mesh buffers/textures | `MetalMesh`, `MetalTexture`, `MetalSceneResources` |
| Gaussian output/counters | `MetalGaussianBuffer` |
| Sort work buffers | `MetalGaussianSortBuffer` |
| Pipelines | `MetalPipelineCache` |
| Sampler/depth state | `MetalRenderStateCache` |
| Frame uniforms | `MetalFrameUniformBuffer` |

## Build Targets

- `Mesh2Splat`: legacy OpenGL target. Retained for historical comparison.
- `Mesh2SplatMetal`: native macOS target. This is the only supported macOS runtime path.

## Architecture Rules

- New macOS rendering work must go into `src/renderer/metal`.
- New macOS UI work must go into `src/app/macos` until the SwiftUI app layer is introduced.
- Core files must remain graphics-API neutral.
- OpenGL includes and symbols must not appear in `src/core`, `src/app/macos`, `src/renderer/metal`, or `shaders/metal`.
- Any temporary compatibility behavior must be documented before it is accepted into a stage.

## Stage 0 Acceptance

The target layout is frozen enough that new code has an obvious home and the old OpenGL renderer is clearly separated from the macOS Metal runtime.
