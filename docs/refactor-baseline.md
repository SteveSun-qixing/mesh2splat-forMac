# Mesh2Splat macOS Metal Refactor Baseline

This document freezes the current migration baseline for the macOS native Metal port.

## Project Snapshot

- Project root: `/Users/sevenstars/Documents/4DGS/mesh2splat/Project-01/mesh2splat-forMac`
- Active branch: `mac-metal-refactor`
- Remote: `origin = git@github.com:SteveSun-qixing/mesh2splat-forMac.git`
- Current macOS target: `Mesh2SplatMetal`
- Current legacy target: `Mesh2Splat`

## Local Toolchain

- CMake: `4.3.3`
- Apple clang: `Apple clang version 17.0.0 (clang-1700.6.3.2)`
- Target architecture: `arm64-apple-darwin24.6.0`
- pkg-config: `2.5.1`
- pkg-config glfw3: `3.4.0`
- GLEW: `2.3.1`
- Homebrew cmake: `4.3.3`
- Homebrew glfw/pkg-config direct package lookup returned no package line, but `pkg-config` resolves glfw3.

## Hardware And Metal Support

`system_profiler SPDisplaysDataType` reports:

- GPU: Apple M2
- GPU cores: 10
- Metal: Supported

## Current Build State

Validated command:

```sh
cmake --build build-mac --target Mesh2SplatMetal -j8
```

Result:

```text
[100%] Built target Mesh2SplatMetal
```

Current linked frameworks for the Metal target:

```text
AppKit.framework
Metal.framework
MetalKit.framework
CoreFoundation.framework
Foundation.framework
```

The Metal target does not link OpenGL, GLFW, or GLEW.

## Shader Toolchain State

Offline Metal shader compilation is not available on this machine yet:

```text
error: cannot execute tool 'metal' due to missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain
```

The current app therefore still needs the runtime shader source fallback path while the Xcode Metal Toolchain component remains missing.

## Legacy OpenGL Failure Cause

The original renderer requests an OpenGL 4.5/4.6 class feature set, including:

- GLSL 450/460 style shaders.
- Compute shaders.
- Shader storage buffer objects.
- Atomic counters.
- Geometry shader based mesh-to-gaussian conversion.
- Indirect draw and OpenGL stateful render passes.

macOS native OpenGL is capped at OpenGL 4.1 and is deprecated. This is a platform capability mismatch, not a missing package problem. Upgrading macOS OpenGL is not possible, and Docker on macOS does not provide direct Apple GPU OpenGL 4.6 access.

## Current Migration Baseline

The macOS path is now represented by `Mesh2SplatMetal`, a separate native app target using AppKit/MTKView and Metal. The legacy OpenGL target remains as historical reference only and must not be used as the macOS runtime path.

Stage 0 baseline conclusion:

- Continue migration as native Metal.
- Keep CPU-only mesh, material, camera, and gaussian data in `src/core`.
- Keep Metal-specific resources in `src/renderer/metal`.
- Keep macOS window/input glue in `src/app/macos`.
- Do not attempt to revive the OpenGL renderer for macOS.
