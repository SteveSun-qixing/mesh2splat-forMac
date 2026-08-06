# Migration Priority

This document freezes the migration priority so the port progresses stage by stage.

> **Status note (2026-08-06)**: Priorities 1-4 below are effectively **complete**
> (stages 0-10 accepted; the SwiftUI frontend, shadow maps, split-screen and PBR
> landed 2026-07-06; the legacy OpenGL path was removed 2026-08-06). The only open
> work is Stage 11 (export/testing/perf records) — see `stage-11-acceptance.md`.
> The priority lists below are kept as historical freeze.

## Execution Rule

From this point forward, stages are advanced by gate:

1. Audit the earliest incomplete stage.
2. Complete all must-have acceptance criteria for that stage.
3. Commit and push the stage or coherent stage subtask.
4. Move to the next stage only after the previous stage is accepted.

## Priority 1: First Native Gaussian Loop

These features must be completed before product polish:

- Native macOS app shell.
- Metal device/context/command infrastructure.
- GLB loading into API-neutral core data.
- Mesh upload to Metal private resources.
- Mesh render with material textures.
- Mesh-to-gaussian conversion on Metal.
- Gaussian count readback.
- Gaussian render path.
- PLY export path.

## Priority 2: Correctness And Interactive Performance

These features come after the first loop is functional:

- GPU depth sorting.
- Conversion regression tests.
- Resource lifetime tracking.
- Performance stats.
- Metal capture process.
- Debug visualization modes.
- PBR material parity.

## Priority 3: Advanced Rendering

These features are intentionally deferred until the base loop is reliable:

- Shadow maps.
- Advanced relighting.
- Deferred gaussian G-buffer.
- Split-screen comparison/debug tools.
- Higher quality transparency refinements.

## Priority 4: Native Product Experience

These features are later-stage work:

- SwiftUI native frontend.
- Full import/export workflow UI.
- Benchmark UI.
- Packaging and release workflow.
- Visual regression gallery.

## Current Stage Gate

**Updated 2026-08-06**: Stage 0-10 gates are closed. The project is now executing
Stage 11 (export, tests and performance engineering):

- PLY export path: implemented (GPU readback + Pbr3DGS writer), end-to-end sample validation pending.
- Basic correctness tests: `CoreIoSmokeTest` implemented and passing (2026-08-06).
- GPU smoke test (`MetalGpuSmokeTest`) and CLI (`Mesh2SplatConvert`): CMake targets declared, source files pending — 待实现 / 待运行验证.
- Benchmark, Metal capture checklist and visual regression gallery: records pending.

See `stage-11-acceptance.md` for the acceptance record.

## Stage 0 Acceptance

Every feature category has a priority, and the first-loop scope is frozen. New work should not expand the scope of the current stage without updating this document.
