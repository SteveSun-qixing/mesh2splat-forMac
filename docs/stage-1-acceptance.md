# Stage 1 Acceptance - macOS App Shell

This document records the Stage 1 gate for the native macOS Metal app shell.

## Stage 1 Scope

Stage 1 requires a native macOS app shell, not full mesh/gaussian feature parity.

Required outcomes:

- macOS native window.
- MTKView-backed frame loop.
- Metal device and command queue path.
- Input event bridge to API-neutral `InputState`.
- Renderer interface boundary between AppKit and backend.
- macOS Metal target that does not link OpenGL/GLFW/GLEW.

## Evidence

### Build Target

Validated command:

```sh
cmake --build build-mac --target Mesh2SplatMetal -j8
```

Result:

```text
[100%] Built target Mesh2SplatMetal
```

### Native App Shell

Implemented files:

- `src/app/macos/MacApp.mm`
- `src/app/macos/MetalView.mm`
- `src/app/macos/MetalView.hpp`

The app creates:

- `NSApplication`
- `NSWindow`
- `Mesh2SplatMetalView : MTKView`
- `MTKViewDelegate` frame loop

The window title is `Mesh2Splat Metal`, and the app terminates after the last window closes.

### Metal View Setup

`Mesh2SplatMetalView` creates a system default `MTLDevice`, sets:

- `MTLPixelFormatBGRA8Unorm`
- `MTLPixelFormatDepth32Float`
- 60 FPS preferred frame rate
- continuous drawing
- framebuffer-only drawable policy

### Input Bridge

`MetalView.mm` maps macOS events into `mesh2splat::core::InputState`:

- mouse move/drag
- mouse buttons
- scroll wheel
- key down/up

No GLFW input state is used by the macOS app shell.

### Renderer Boundary

AppKit now includes only:

```cpp
#include "renderer/RendererInterface.hpp"
```

It constructs the backend through:

```cpp
mesh2splat::renderer::createMetalRenderer(...)
```

The AppKit layer no longer includes `renderer/metal/MetalRenderer.hpp`.

### Link Check

Current Metal target link dependencies include:

- AppKit
- Metal
- MetalKit
- CoreFoundation
- Foundation

The Metal target does not link OpenGL, GLFW, or GLEW.

## Caveat

Offline `.metallib` generation is still skipped locally because Xcode's Metal Toolchain component is missing:

```text
Metal shader tools are unavailable; skipping .metallib generation for now.
Install them with: xcodebuild -downloadComponent MetalToolchain
```

This does not block Stage 1 because runtime shader source fallback exists. It remains a later build/toolchain item before release-quality packaging.

## Gate Result

Stage 1 is accepted. The project may proceed to Stage 2 audit.
