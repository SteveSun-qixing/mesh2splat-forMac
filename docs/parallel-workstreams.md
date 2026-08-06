# Parallel Workstreams

This document converts the original sequential migration plan into parallel lanes. Each lane can move independently when its write scope is isolated and the integration owner keeps the Metal target buildable.

> **Status note (2026-08-06)**: the SwiftUI lane has **landed** (2026-07-06 commits),
> Metal shadow/PBR/split-screen work is complete, and the legacy OpenGL path was
> **removed** on 2026-08-06 (`4ef4d60`). Remaining active work is Stage 11: GPU smoke
> test, CLI converter, and performance/verification records. The lane table below is
> kept as historical record.

## Integration Rules

- Keep macOS runtime work on `mac-metal-refactor`.
- Commit and push after each stable small task.
- Prefer local smoke tests for Core/IO and targeted Metal target builds for renderer changes.
- Do not edit the same ownership area from multiple workers at the same time.
- Use full `Mesh2SplatMetal` build and link checks after a lane reaches a coherent integration point.

## Active Lanes

| Lane | Ownership | Current Focus | Can Run In Parallel With |
|---|---|---|---|
| Core / IO | `src/core`, `src/io`, `tests/CoreIoSmokeTest.cpp` | API-neutral scene, camera, Gaussian ABI, GLTF/PLY boundaries | Metal backend, docs, SwiftUI planning |
| Metal Infrastructure | `src/renderer/metal/MetalDeviceContext.*`, `MetalBuffer.*`, `MetalTexture.*`, `MetalPipelineCache.*`, `MetalShaderLibrary.*` | Resource labels, capability reporting, pipeline diagnostics, upload modes | Core / IO, UI planning |
| Mesh Upload / Materials | `src/renderer/metal/MetalMesh.*`, `MetalSceneResources.*`, `MetalMeshRenderPass.*` | Texture fallback correctness, material constants, private resource upload | UI planning, tests/docs |
| Conversion / Gaussian Loop | `MetalConversionPass.*`, `MetalGaussianBuffer.*`, `MetalGaussianRenderPass.*`, `MetalGaussianSortPass.*`, `shaders/metal/*.metal` | GPU conversion, count readback, gaussian draw and sort correctness | SwiftUI planning, docs |
| App Shell / SwiftUI | `src/app/macos`, SwiftUI app target | SwiftUI workbench landed 2026-07-06; workbench polish ongoing | Core / IO, Metal backend |
| Verification / Docs | `docs`, `tests`, CMake test targets | Acceptance evidence, smoke tests, migration notes. Stage 11 records; GPU smoke test + CLI pending | All lanes |

## Near-Term Parallel Backlog

| Task | Lane | Output | Suggested Validation |
|---|---|---|---|
| Core/IO smoke test | Core / IO | `CoreIoSmokeTest` CMake target | `cmake --build build-mac --target CoreIoSmokeTest -j8 && ./build-mac/CoreIoSmokeTest` |
| Stage 2 acceptance record | Verification / Docs | `docs/stage-2-acceptance.md` | Search checks for Core/IO graphics API neutrality |
| Metal capability snapshot | Metal Infrastructure | Capability fields in `MetalDeviceContext` and docs | `Mesh2SplatMetal` build |
| Resource label audit | Metal Infrastructure | Clear labels for buffers/textures/pipelines | Metal target build and code search |
| Mesh texture fallback audit | Mesh Upload / Materials | Confirm fallback textures and material mapping | Metal target build |
| SwiftUI boundary plan | App Shell / SwiftUI | SwiftUI integration design doc | Done - see `docs/swiftui-app-architecture.md`, workbench landed 2026-07-06 |

## Integration Cadence

The project no longer blocks on finishing an entire numbered stage before starting the next. A lane may start future-stage work when:

- Its write set does not conflict with active work.
- The change makes the native Metal/macOS end state more true.
- The integration owner can keep a small, reproducible validation command for it.

Stage documents remain useful as requirement checklists, but the execution model is now parallel lanes plus frequent stable commits.
