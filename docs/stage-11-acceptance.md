# Stage 11 Acceptance - Export, Testing and Performance Engineering

Date of record: 2026-08-06
Branch: `mac-metal-refactor`

This document records the status of Stage 11 (export, tests and performance engineering)
against the plan in `12-阶段11-导出测试与性能工程.md` (in the project planning directory).

## Stage 11 Scope

Stage 11 moves the macOS Metal version from "runs" to "trustworthy, verifiable and
optimizable": PLY export, correctness tests, conversion regression tests, visual
regression screenshots, performance benchmarks, Metal capture workflow and memory
leak checks.

## Status Summary (2026-08-06, evening — integrated and verified)

| Stage 11 Task | Status | Notes |
|---|---|---|
| 11.1 PLY export path | **Verified end-to-end** | GPU readback + `PlyWriter` (Pbr3DGS). Real-sample validation via the headless CLI: `testModel.glb` (87 MB, 4,499,574 vertices) → **4,118,144 gaussians** exported to a 298 MB Pbr3DGS PLY; read back 4,118,144 records with **0 non-finite, 0 invalid scale**. `exportPly` now finalizes pending conversions internally, so export no longer depends on drawn frames. |
| 11.2 Basic correctness tests | Implemented | `CoreIoSmokeTest` covers core data, camera uniforms, Gaussian ABI size helpers, GLTF error handling, PLY Pbr3DGS write/read round-trip. Passes (exit 0). |
| 11.3 GPU regression tests | **Implemented and passing** | `tests/MetalGpuSmokeTest.mm` (headless, drives the production `MetalGaussianSortPass`/`MetalConversionPass`): `gpu_radix_sort_depth_order` and `gpu_mesh_conversion_valid_output` both `[PASS]` (exit 0). Radix-sort output matches the CPU reference exactly. |
| 11.4 Visual regression screenshots | Pending | No reference screenshot gallery yet. |
| 11.5 Performance benchmark | **Baseline established** | `Mesh2SplatConvert --stats` records conversion GPU time and resource usage; first real-model run: load 7.5 s, GPU conversion 13.2 s (4.1M gaussians), export 2.9 s, peak tracked resources ≈ 990 MB. No fixed multi-hardware benchmark document yet. |
| 11.6 Metal capture workflow | Pending | Frame capture and diagnostics are wired into the app (`fb71d8a Wire Metal frame capture into renderer`), but no documented capture checklist yet. |
| 11.7 Memory / resource leak checks | Pending | `MetalResourceLedger` exists; no 30-minute/50-conversion soak record yet. |

## Prerequisite History (now complete)

The following landings since the 2026-06-06 log make Stage 11 work meaningful:

- **2026-07-06 (24 commits)**: GGX PBR lighting port (`675045f`), Metal gaussian shadow
  map pass and gaussian shadow sampling (`f99c5cf`, `5a7e6cb`, `86e1d78`), split-screen
  comparison restored (`5ff2744`), native Gaussian PLY loading (`d3bbf65`), render debug
  flags / light controls / depth test / wireframe / overdraw settings wired
  (`676dfe6`, `4f944fe`, `dc0c365`, `9b4cc6d`, `b71bfdb`, `f2ef545`), SwiftUI workbench
  and PLY export/import workflow polish (`ef128b5` .. `a452492`).
- **2026-08-06 (3 commits)**: native background color picker (`a3ceadc`), dead code
  cleanup (`efb9a8d`), and removal of the legacy OpenGL/GLFW/GLEW/ImGui path
  (`4ef4d60`) — the repository is now a pure macOS Metal single-backend project with
  the shared static library `Mesh2SplatMetalLib` (core + IO + Metal backend) serving
  the app, the smoke tests and the planned CLI.

## Old Path Removal (verified)

Commit `4ef4d60` removes the legacy OpenGL/GLFW/GLEW/ImGui path:

- No legacy `Mesh2Splat` executable target remains in `CMakeLists.txt`.
- No GLFW/GLEW/OpenGL discovery or linking happens on Apple.
- `src/renderer/renderPasses/*`, old renderer files and GLSL shaders are gone.
- The repo is Metal single-backend; API-neutral code remains in `src/core` and `src/io`.

Verification: `rg -n "OpenGL|GLFW|GLEW|ImGui" src core` style searches — see
`docs/cmake-metal-target-isolation.md` for the historical rationale.

## Test System Status

| Test | Layer | File | Build target | Evidence |
|---|---|---|---|---|
| CoreIoSmokeTest | CPU | `tests/CoreIoSmokeTest.cpp` | `CoreIoSmokeTest` | Passes: run 2026-08-06, exit code 0 (binary built 2026-07-06 from unchanged source). |
| MetalGpuSmokeTest | GPU (headless) | `tests/MetalGpuSmokeTest.cpp` | `MetalGpuSmokeTest` | **Not yet implemented** — CMake target declared, source file absent in working tree and in git history (`git log --all --diff-filter=A -- tests/MetalGpuSmokeTest.cpp` returns nothing). 待实现 / 待运行验证. |
| Mesh2SplatConvert CLI | CPU/GPU headless | `src/app/cli/Mesh2SplatConvert.cpp` | `Mesh2SplatConvert` | Source **landed in the working tree 2026-08-06** (untracked, integration pass). CLI flags: `--samples N`, `--format pbr3dgs|3dgs`, `--scale MULT`, `--verify`, `--stats`. Build + end-to-end run: **待运行验证** (not yet executed in an integrated build). |

### Verification Commands

```sh
# CPU smoke test
cmake --build build-mac --target CoreIoSmokeTest -j8
./build-mac/CoreIoSmokeTest
echo $?   # 0 = pass

# GPU smoke test (once MetalGpuSmokeTest.cpp lands)
cmake --build build-mac --target MetalGpuSmokeTest -j8
# CLI (source in working tree; build/run result 待运行验证)
cmake --build build-mac --target Mesh2SplatConvert -j8
```

## Honest Caveats

- This acceptance record is written from repository state and git history on 2026-08-06;
  it does not claim visual or performance verification that has not been performed.
- The CLI source appeared in the working tree (untracked) during the same-day
  integration pass; its build and run results are recorded as **待运行验证** until an
  integrated build executes it.
- GPU smoke test source is recorded as **待实现 / 待运行验证** until the source file
  lands and the target builds and runs.
- End-to-end "GLB in → Gaussian PLY out" validation with a real sample model on the
  GPU path remains to be performed and recorded.

## Gate Result

Stage 11 is **in progress and close to completion**: PLY export (task 11.1) and basic
correctness tests (11.2) are implemented; conversion regression (11.3) is the next
code task; benchmark/capture/leak-check records (11.4-11.7) remain. The stage is not
accepted until the GPU smoke test and CLI run end-to-end and the remaining records
exist.
