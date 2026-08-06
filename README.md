# Mesh2Splat
<div align="center">
    <img src="./res/mesh2splatPipelineFinal.jpg" width="750px">
</div>

**Mesh2Splat** is a fast surface splatting approach used to convert 3D meshes into 3DGS [(3D Gaussian Splatting)](https://repo-sam.inria.fr/fungraph/3d-gaussian-splatting/) models by exploiting the rasterizer's interpolator.<br>Mesh2Splat comes with a **3DGS Renderer** to view the conversion results.<p>

> "**What if we wanted to represent a synthetic object (3D model) in 3DGS format?**"

Currently, the only way to do so is to generate a synthetic dataset (camera poses, image renders and initial sparse point cloud) of the 3D model, and then feed this into the 3DGS pipeline. This process can take several minutes, depending on the specific 3DGS pipeline and model used.
<br>

**Mesh2Splat** instead, by directly using the geometry, materials and texture information from the 3D model, rather than going through the classical 3DGS pipeline, is able to obtain a 3DGS representation of the input 3D models in milliseconds.<br>

> **Note**: This repository is the **macOS native refactor** of the upstream [Electronic Arts / Mesh2Splat](https://github.com/electronicarts/mesh2splat) project. The legacy OpenGL/GLFW/GLEW/ImGui code path has been removed; macOS Metal is now the only backend. The upstream project description, method, citation and licensing below are preserved from the original repository.

## Use Cases

**Mesh2Splat** is built for fast and flexible integration into 3D Gaussian Splatting (3DGS) workflows, especially when traditional pipelines may be too slow or incompatible with certain scenarios. Below are some key use cases:

- **3DGS-only Rendering Pipelines**  
  Some 3DGS renderers do not support hybrid rendering (i.e., mixing triangle meshes and Gaussians). In these cases, Mesh2Splat enables direct conversion of mesh assets into pure 3DGS format, allowing them to be rendered natively without relying on slower optimization pipelines.

- **Fast Initialization for 3DGS Optimization**  
  When preparing a model for a 3DGS optimization pipeline (e.g., with new sets of images or altered appearance), having a good initial guess is crucial for faster convergence and better results. Mesh2Splat provides a geometry and texture informed initialization that can be used as a strong starting point for further refinement.

- **Enhancing Traditional Renderers with Gaussian Primitives**  
  In pipelines where triangle meshes are the primary representation but 3DGS rendering is supported, Mesh2Splat can be used to convert selected assets into Gaussians. This enables developers and artists to leverage the unique properties of Gaussians.

## Features (macOS Native Implementation)

### Converter

- **Direct 3D Model Processing**: Directly obtain a 3DGS model from a 3D mesh (`.glb` / `.gltf` import supported).
- **GPU conversion**: Mesh-to-splat conversion runs as a pure Metal compute kernel (`Conversion.metal`) with GPU counter readback.
- **Sampling density**: conversion quality is tweakable in the workbench settings.
- **Texture map support**: Diffuse, Metallic-Roughness and Normal maps.
- **Relightability**: Gaussians can be relit in the built-in PBR renderer.
- **PLY export / import**: Gaussian PLY export and import in Pbr3DGS format (position, color, scale, rotation, normal, PBR factors).

### 3DGS Renderer (Metal)

- **Visualization options**: albedo, normals, depth, geometry, overdraw, PBR properties and more (7 visualization modes).
- **Gaussian shading**: GGX PBR based shading ported to Metal shaders.
- **Lighting and shadows**: point light lighting with Metal shadow map passes for both meshes and Gaussians.
- **Split-screen comparison**: restored native split-screen comparison between render paths.
- **Mesh-Gaussian occlusion**: "Enable mesh-gaussian depth test" uses the mesh as occluder in the depth prepass.
- **Debug views**: wireframe, overdraw, conversion enablement, render debug flags wired through the SwiftUI workbench.

### SwiftUI Workbench

- Native SwiftUI macOS frontend: scene import/export workflow, render/convert controls, render presets, diagnostics, resource telemetry, conversion progress, background color picker and viewport toolbar.

<div align="center">
    <img src="./res/conversion.gif" width="850px">
</div>

**3D model by**: M. Pavlovic, "Sci-fi helmet model," 2024, provided by Quixel. License: CC Attribution Share Alike 3.0. (https://creativecommons.org/licenses/by-sa/3.0/.), you can download it from [here](https://github.com/KhronosGroup/glTF-Sample-Assets/tree/main/Models/SciFiHelmet/glTF)

## Method
The (current) core concept behind **Mesh2Splat** is rather simple:
- Compute 3D model bounding box
- Initialize a 2D covariance matrix for our 2D Gaussians as: <br>
$`{\Sigma_{2D}} = \begin{bmatrix} \sigma^{2}_x & 0 \\\ 0 & \sigma^{2}_y \end{bmatrix}`$ <br><br> where: $`{\sigma_{x}}\sim {\sigma_{y}}\sim 0.65`$ <br>and $`{\rho} = 0`$
- Then, for each triangle primitive in the Geometry Shader stage, we do the following:
    - Apply triplanar orthogonal projection onto X,Y or Z face based on normal similarity and normalize in [-1, 1].
    - Compute Jacobian matrix from *orthogonal UV space* to *3D space* for each triangle:  $`J = V \cdot (UV)^{-1} `$.
    - Derive the 3D directions corresponding to texture axes $`u`$ and $`v`$, and calculate the magnitudes of the 3D derivative vectors.
    - Multiply the found lengths by the 2D Gaussian´s standard deviation, this way we found the scaling factors along the directions aligned with the surface in 3D space.
    - The packed scale values will be: 
        - $`packedScale_x = log(length(Ju) * sigma_x)`$
        - $`packedScale_y = log(length(Jv) * sigma_y)`$
        - $`packedScale_z = log(1e-7)`$
    

- Now that we have the **Scale** and **Rotation** for a *3D Gaussian* part of a specific triangle, emit one 3D Gaussian for each vertex of this triangle, setting their respective 3D position to the 3D position of the vertex, and in order to exploit the hardware interpolator, we set ```gl_Position = vec4(gs_in[i].normalizedUv * 2.0 - 1.0, 0.0, 1.0);```. This means that the rasterizer will interpolate these values and generate one 3D Gaussian per fragment in the orthogonal space.
- Perform texture fetches and set this data per gaussian in Fragment Shader. 
- Each fragment now atomically appends one gaussian into a shared [SSBO](https://www.khronos.org/opengl/wiki/Shader_Storage_Buffer_Object). 

> **Note**: In this macOS native port, the geometry-shader based conversion is replaced by a pure Metal compute conversion kernel (`shaders/metal/Conversion.metal`) that reproduces the same triplanar-projection / Jacobian math on the GPU.

## Performance
Mesh2Splat is able to convert a 3D mesh into a 3DGS on average in **<0.5ms** (upstream figure; native Metal conversion timing is tracked in the workbench performance stats).

## Build Instructions (macOS)

### Prerequisites

- **macOS 14 or later** (Metal 3 capable Apple Silicon or Intel Mac).
- **Xcode Command Line Tools** or a full Xcode installation, including the **Metal shader toolchain** (`xcrun -sdk macosx --find metal` must succeed). If the Metal compiler is missing, install it with:
  ```sh
  xcode-select --install
  # or, for the Metal toolchain component inside Xcode:
  xcodebuild -downloadComponent MetalToolchain
  ```
- **CMake ≥ 3.15** (any recent CMake works; 3.21+ recommended).
- **Ninja** (recommended): `brew install ninja`.

> The SwiftUI workbench is compiled from Swift sources. CMake enables Swift only for the **Ninja** (or Xcode) generators. With `Unix Makefiles`, CMake automatically falls back to the AppKit-only frontend (no SwiftUI panels). Use Ninja to get the full SwiftUI workbench.

### Build Steps

1. Configure with Ninja (recommended, full SwiftUI workbench):
   ```sh
   cmake -B build-mac -G Ninja
   cmake --build build-mac -j8
   ```
   Alternative configure without Ninja (AppKit-only frontend):
   ```sh
   cmake -B build-mac-make
   cmake --build build-mac-make -j8
   ```

2. Build outputs:
   - App bundle: `bin/Metal/Mesh2SplatMetal.app`
   - Static library: `libMesh2SplatMetalLib.a` (in the build directory)
   - Smoke tests and CLI tools: see [Tests](#tests) below.

3. The `.metal` shaders are compiled offline into `Mesh2SplatMetal.metallib` and copied into the app bundle automatically.

> **Tip**: Use `cmake -B build-mac -G Ninja -DCMAKE_BUILD_TYPE=Release` for an optimized build.

## Run

```sh
open bin/Metal/Mesh2SplatMetal.app
```

The workbench opens a native macOS window. Drag & drop (or use File > Open) a `.glb` / `.gltf` / Gaussian `.ply` file to load a scene, convert the mesh to Gaussians, inspect the 7 visualization modes, adjust lighting, and export the result as Gaussian PLY (Pbr3DGS).

## Command Line Converter

`Mesh2SplatConvert` converts a mesh (or Gaussian PLY) to Gaussian PLY headlessly, linked against `Mesh2SplatMetalLib`:

```sh
Usage: Mesh2SplatConvert <input.(glb|gltf|ply)> <output.ply> [options]
  --samples N         gaussian samples per mesh triangle (default 8)
  --format NAME       export format: pbr3dgs (default) or 3dgs
  --scale MULT        gaussian scale multiplier applied on export (default 1.0)
  --verify            read the exported PLY back and validate gaussian records
  --stats             print renderer resource and timing statistics
```

Example:

```sh
cmake --build build-mac --target Mesh2SplatConvert -j8
./bin/Mesh2SplatConvert model.glb model.ply --samples 8 --format pbr3dgs --verify --stats
```

The shader library is resolved through `MESH2SPLAT_METALLIB_PATH` (falling back to the app bundle path / runtime source fallback).

> **Status**: the CLI source landed in the working tree on 2026-08-06 as part of the
> Stage 11 integration pass. Build and end-to-end run results are 待运行验证 until
> the integrated build executes the tool.

## Tests

| Test | Layer | Status |
|---|---|---|
| `CoreIoSmokeTest` (`tests/CoreIoSmokeTest.cpp`) | CPU side: core data, camera, Gaussian ABI, GLTF error handling, PLY Pbr3DGS write/read round-trip | Implemented; passes on 2026-08-06 |
| `MetalGpuSmokeTest` (`tests/MetalGpuSmokeTest.cpp`) | GPU side, headless Metal compute/conversion smoke test | Planned; CMake target declared, source pending |

Run the CPU smoke test:

```sh
cmake --build build-mac --target CoreIoSmokeTest -j8
./build-mac/CoreIoSmokeTest
```

Exit code 0 means all checks passed.

## Architecture Overview

The project is organized in three layers around the shared static library `Mesh2SplatMetalLib`:

```text
src/
  core/                 # API-neutral data, math, camera, parsing outputs
  io/                   # API-neutral import/export: GltfLoader, PlyReader, PlyWriter
  renderer/metal/       # Metal resources, passes, pipelines, command scheduling
  app/
    macos/              # AppKit, MTKView, SwiftUI workbench, RendererBridge
    cli/                # Mesh2SplatConvert CLI (planned)
shaders/
  metal/                # MSL sources: Mesh, Conversion, Gaussian, Sort, Shadow, GpuTypes
tests/                  # CoreIoSmokeTest (GPU smoke test planned)
docs/                   # Migration and verification documentation
```

- `Mesh2SplatMetalLib` is a static library combining the API-neutral core, the IO layer and the Metal renderer backend. It has **no AppKit/MTKView dependencies**, so the same library serves the macOS app, headless tests and the CLI.
- The **app** (`Mesh2SplatMetal`) adds the native macOS frontend: SwiftUI workbench (Ninja/Xcode builds) or AppKit-only shell (Makefiles), speaking to the renderer through `RendererInterface`.
- The **CLI** (`Mesh2SplatConvert`) is the planned headless converter.

## Documentation

The `docs/` directory contains the migration and verification documentation:

- [target-architecture.md](docs/target-architecture.md) — frozen target layout and backend boundaries
- [mac-metal-native-port-plan.md](docs/mac-metal-native-port-plan.md) — original port plan (Chinese)
- [migration-priority.md](docs/migration-priority.md) — stage gate priorities
- [parallel-workstreams.md](docs/parallel-workstreams.md) — parallel work lanes
- [stage-1-acceptance.md](docs/stage-1-acceptance.md) / [stage-11-acceptance.md](docs/stage-11-acceptance.md) — stage acceptance records
- [refactor-baseline.md](docs/refactor-baseline.md) — migration baseline snapshot
- [shader-inventory.md](docs/shader-inventory.md) / [pass-inventory.md](docs/pass-inventory.md) — GLSL → MSL and pass migration maps
- [gpu-data-layout.md](docs/gpu-data-layout.md), [metal-buffer-memory-policy.md](docs/metal-buffer-memory-policy.md), [metal-frame-resources-notes.md](docs/metal-frame-resources-notes.md), [metal-gaussian-sort-notes.md](docs/metal-gaussian-sort-notes.md), [metal-mesh-material-upload-notes.md](docs/metal-mesh-material-upload-notes.md), [metal-shader-library-strategy.md](docs/metal-shader-library-strategy.md), [swiftui-app-architecture.md](docs/swiftui-app-architecture.md), [cmake-metal-target-isolation.md](docs/cmake-metal-target-isolation.md), [apple-silicon-performance-verification.md](docs/apple-silicon-performance-verification.md)

## Limitations
- Volumetric Data such as foliage, grass, hair, clouds, etc. has not being targeted and will probably not be converted correctly if using primitives different from triangles.<br>

## How to Cite
To cite this repository, click the **"Cite this repository"** button at the top of the GitHub page.  
Alternatively, you can use the following BibTeX entry:
```bibtex 
@misc{
scolari2025mesh2splat,
author = {Scolari, Stefano},
title = {Mesh2Splat: Fast mesh to 3D Gaussian splat conversion},
year = {2025}, howpublished = {\url{https://github.com/electronicarts/mesh2splat}},
note = {Extended and updated version of the author's Master's thesis at KTH.} 
}
```
This work builds upon the authors Master Thesis work:
```bibtex 
@mastersthesis{
scolari2024thesis,
author = {Scolari, Stefano},
title = {Mesh2Splat: Gaussian Splatting from 3D Geometry and Materials},
school = {KTH Royal Institute of Technology},
year = {2024},
url = {https://urn.kb.se/resolve?urn=urn:nbn:se:kth:diva-359582}
}
```

# Authors

<div align="center">
<b>Search for Extraordinary Experiences Division (SEED) - Electronic Arts
<br>
<a href="https://seed.ea.com">seed.ea.com</a>
<br>
<a href="https://seed.ea.com"><img src="./res/seed-logo.png" width="150px"></a>
<br>
SEED is a pioneering group within Electronic Arts, combining creativity with applied research.</b> <br>
We explore, build, and help define the future of interactive entertainment.
</p>

Mesh2splat is an Electronic Arts project created by [Stefano Scolari](https://www.linkedin.com/in/stefano-scolari/) for his Master's Thesis at [KTH](https://www.kth.se/en) while interning at [SEED](https://www.ea.com/seed) and supervision of Martin Mittring (Principal Rendering Engineer at [SEED](https://www.ea.com/seed)) and Christopher Peters (Professor in HCI & Computer Graphics at [KTH](https://www.kth.se/en)).

# Contributing

Before you can contribute, EA must have a Contributor License Agreement (CLA) on file that has been signed by each contributor. You can sign [here](https://electronicarts.na1.echosign.com/public/esignWidget?wid=CBFCIBAA3AAABLblqZhByHRvZqmltGtliuExmuV-WNzlaJGPhbSRg2ufuPsM3P0QmILZjLpkGslg24-UJtek*).

# License

The source code is released under an open license as detailed in [LICENSE.txt](./LICENSE.txt)
