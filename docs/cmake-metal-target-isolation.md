# CMake Metal Target Isolation Plan

This document records the current CMake target-isolation problem on macOS and proposes a follow-up refactor. Task 19 is documentation-only: no `CMakeLists.txt` or source files are changed here.

> **Status note (2026-08-06)**: this problem is **resolved beyond the proposal**. Commit
> `4ef4d60` removed the legacy OpenGL target, GLFW/GLEW/OpenGL discovery and the old
> third-party include pollution entirely; the project is now a Metal single-backend
> tree with the shared `Mesh2SplatMetalLib`. The remainder of this document is kept as
> the historical analysis and proposal.

## Current State

The root `CMakeLists.txt` still configures the legacy OpenGL application before the macOS Metal application:

- Directory-scoped includes are added before any target exists:
  - `${CMAKE_SOURCE_DIR}/src`
  - legacy/system third-party paths for GLFW, GLEW, GLM, ImGui, ImGuiFileDialog, ImGuizmo, xatlas, and `thirdParty`
- `file(GLOB_RECURSE SOURCES ...)` collects broad `src/*.cpp`, `src/*.hpp`, and `src/*.h` inputs for the legacy executable.
- `add_executable(Mesh2Splat ${SOURCES})` is unconditional, so the legacy OpenGL target is created on Apple.
- The Apple branch for `Mesh2Splat` requires `pkg-config`, `glfw3`, `glew`, and `OpenGL.framework`, then links those libraries to the legacy target.
- The native macOS target, `Mesh2SplatMetal`, is added later inside `if(APPLE)` with its own explicit source list and Metal/AppKit framework links.

The practical result is that a native Metal macOS configure still carries the legacy OpenGL target and its dependency discovery unless the build command only asks for `Mesh2SplatMetal`.

## Problems

### Legacy OpenGL Remains A macOS Target

`Mesh2Splat` is retained for historical comparison, but it is still a first-class target on Apple. That keeps the old OpenGL stack active during configure and generation, even though the accepted macOS runtime path is `Mesh2SplatMetal`.

This matters because macOS OpenGL is capped below the legacy renderer's required feature set. The target should remain available only when explicitly requested for reference or comparison work.

### Global Include Directories Pollute Later Targets

The current `include_directories(...)` calls are directory scoped. They apply to targets declared later in the same directory, including `CoreIoSmokeTest` and `Mesh2SplatMetal`.

That makes GLFW, GLEW, ImGui, and other legacy/support include paths visible outside the target that actually needs them. It weakens the intended boundaries:

- Core/IO code can accidentally include graphics or UI dependencies and still compile.
- Metal code can accidentally see legacy OpenGL headers.
- Include-order collisions can be masked by broad global search paths.
- Future tests cannot reliably prove that a target's public/private dependency set is clean.

### Configure-Time Dependencies Do Not Match The Default macOS Path

A developer building the native macOS app should not need legacy OpenGL packages just to configure the project. The current Apple branch still resolves GLFW, GLEW, and OpenGL for `Mesh2Splat` by default.

The default macOS build should express the migration decision directly: build `Mesh2SplatMetal` by default, and build the legacy OpenGL executable only when requested.

## Target State

On Apple:

- `Mesh2SplatMetal` is the default application target.
- `Mesh2Splat` is opt-in legacy/reference material.
- OpenGL, GLFW, and GLEW discovery only runs when the legacy target is enabled.
- Directory-level `include_directories(...)` is removed.
- Every target declares its own includes through `target_include_directories(...)`.
- Core/IO test targets receive only API-neutral include paths.
- Metal targets receive only `src` plus any Metal-specific framework links they require.
- Legacy OpenGL targets receive GLFW/GLEW/OpenGL includes and link inputs in their own target scope.

On non-Apple platforms:

- Preserve the existing legacy OpenGL default unless a later cross-platform migration changes it deliberately.
- Keep platform-specific third-party lookup inside the branch that creates and links the target that needs it.

## Proposed Options

Add target selection options near the top of the root CMake file. CMake options cannot use generator expressions as initial cache values, so use normal variables before the `option(...)` calls:

```cmake
set(MESH2SPLAT_DEFAULT_BUILD_METAL OFF)
set(MESH2SPLAT_DEFAULT_BUILD_LEGACY_OPENGL ON)
if(APPLE)
    set(MESH2SPLAT_DEFAULT_BUILD_METAL ON)
    set(MESH2SPLAT_DEFAULT_BUILD_LEGACY_OPENGL OFF)
endif()

option(MESH2SPLAT_BUILD_METAL "Build the native macOS Metal application" ${MESH2SPLAT_DEFAULT_BUILD_METAL})
option(MESH2SPLAT_BUILD_LEGACY_OPENGL "Build the legacy OpenGL application" ${MESH2SPLAT_DEFAULT_BUILD_LEGACY_OPENGL})
option(MESH2SPLAT_BUILD_TESTS "Build smoke/regression test targets" ON)
```

Expected default matrix:

| Platform | `MESH2SPLAT_BUILD_METAL` | `MESH2SPLAT_BUILD_LEGACY_OPENGL` | Default app target |
|---|---:|---:|---|
| macOS | `ON` | `OFF` | `Mesh2SplatMetal` |
| Windows | `OFF` | `ON` | `Mesh2Splat` |
| Linux | `OFF` | `ON` | `Mesh2Splat` |

If a developer needs the historical OpenGL target on macOS, they can configure with:

```sh
cmake -S . -B build-mac -DMESH2SPLAT_BUILD_LEGACY_OPENGL=ON
```

## Refactor Steps

1. Introduce the build options without changing source ownership.
2. Move all legacy source globbing and third-party source collection inside `if(MESH2SPLAT_BUILD_LEGACY_OPENGL)`.
3. Create `Mesh2Splat` only inside that option block.
4. Move `target_compile_definitions(Mesh2Splat PRIVATE GLEW_STATIC)` into the same block.
5. Move Windows, Apple, and Linux OpenGL link discovery into the same block, nested by platform.
6. Guard `Mesh2Splat` output-directory properties behind `if(TARGET Mesh2Splat)`.
7. Guard `Mesh2SplatMetal` creation with `if(APPLE AND MESH2SPLAT_BUILD_METAL)`.
8. Replace directory-scoped includes with target-scoped includes.
9. Keep `CoreIoSmokeTest` under `if(MESH2SPLAT_BUILD_TESTS)` and give it only `${CMAKE_SOURCE_DIR}/src`.
10. Reconfigure from a clean build directory to verify that macOS no longer resolves GLFW/GLEW/OpenGL unless the legacy option is enabled.

## Include Scope Plan

Use target-local includes instead of directory includes:

```cmake
target_include_directories(Mesh2Splat PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${GLFW_DIR}/include
    ${GLEW_DIR}/include
    ${GLM_DIR}
    ${IMGUI_DIR}
    ${IGFD_DIR}
    ${IMGUIZMO_DIR}
    ${XATLAS_DIR}
    ${THIRD_PARTY_DIR}
)
```

For macOS pkg-config includes, keep them on the legacy target only:

```cmake
target_include_directories(Mesh2Splat PRIVATE
    ${GLFW_INCLUDE_DIRS}
    ${GLEW_INCLUDE_DIRS}
)
```

Keep the Metal target narrow:

```cmake
target_include_directories(Mesh2SplatMetal PRIVATE
    ${CMAKE_SOURCE_DIR}/src
)
```

Keep Core/IO tests narrow:

```cmake
target_include_directories(CoreIoSmokeTest PRIVATE
    ${CMAKE_SOURCE_DIR}/src
)
```

If repeated target include sets become noisy, add small helper functions such as `mesh2splat_apply_core_includes(target_name)` and `mesh2splat_apply_legacy_includes(target_name)`. Do not reintroduce directory-scoped includes through helpers.

## Validation Checklist

After the CMake refactor, validate these paths:

```sh
cmake -S . -B build-mac-clean
cmake --build build-mac-clean --target Mesh2SplatMetal -j8
```

Expected macOS default behavior:

- `Mesh2SplatMetal` exists and builds.
- `Mesh2Splat` is not generated unless `MESH2SPLAT_BUILD_LEGACY_OPENGL=ON`.
- Configure does not require `pkg-config` glfw3/GLEW for the default Metal-only path.
- `Mesh2SplatMetal` does not link OpenGL, GLFW, or GLEW.

Legacy opt-in validation:

```sh
cmake -S . -B build-mac-legacy -DMESH2SPLAT_BUILD_LEGACY_OPENGL=ON
cmake --build build-mac-legacy --target Mesh2Splat -j8
```

Expected legacy behavior:

- `Mesh2Splat` exists only in the opt-in build.
- GLFW/GLEW/OpenGL discovery failures are reported only in the opt-in build.
- Any macOS OpenGL feature failure remains classified as a legacy platform limitation, not a Metal target regression.

Boundary checks:

```sh
rg -n "#include <GL|#include <GLFW|#include <GL/|#include <OpenGL|#import <OpenGL" src/core src/io src/app/macos src/renderer/metal
cmake --build build-mac-clean --target CoreIoSmokeTest -j8
```

Expected boundary behavior:

- Core, IO, macOS app, and Metal renderer files do not include OpenGL or GLFW headers.
- Core/IO tests still build with only API-neutral includes.

## Non-Goals

- Do not revive or modernize the legacy OpenGL renderer for macOS.
- Do not change the Metal source layout as part of target isolation.
- Do not remove the legacy target entirely; keep it available as explicit reference material.
- Do not make GLFW/GLEW global dependencies of the native macOS path.

## Recommendation

Perform this refactor as a small CMake-only follow-up task. The safest sequence is:

1. Add options and wrap target creation without moving source files.
2. Remove global includes and add target-scoped includes.
3. Reconfigure macOS from a clean directory and verify the default target set.
4. Run an explicit legacy opt-in configure to confirm that comparison builds remain possible.

That leaves the migration architecture consistent with the docs: macOS defaults to `Mesh2SplatMetal`, while `Mesh2Splat` remains available only when someone intentionally asks for the legacy OpenGL path.
