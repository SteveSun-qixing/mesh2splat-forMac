# Metal Shader Library Strategy

Scope: `MetalShaderLibrary.*`, `MetalRenderer.mm` shader loading, CMake metallib
packaging, and pipeline-cache diagnostics.

## Current Implementation

- Runtime load order is fixed in `MetalRenderer`: bundled
  `Mesh2SplatMetal.metallib`, then `MTLDevice::newDefaultLibrary`, then bundled
  `.metal` source files under `Resources/Shaders` compiled with
  `newLibraryWithSource`.
- CMake always copies individual `.metal` sources into the app bundle. When
  `xcrun metal` and `xcrun metallib` are available, it also builds and copies
  `Mesh2SplatMetal.metallib`; otherwise runtime source fallback remains the
  supported path.
- Each failed load clears the active library state and records a diagnostic that
  names the failed source and the next fallback path. Runtime source failure
  reports that no shader-library fallback remains.
- `MetalShaderLibrary` records source kind, stable source kind name, identifier,
  byte count, debug label, source description, sorted public function names, and
  cached `MTLFunction` objects.
- `MetalPipelineCache` uses `missingFunctionDiagnostic()` for render and compute
  pipeline misses, so missing shader symbols include the active library source
  and a capped list of available functions.

## Next Integration Points

- Add a packaging/build check that confirms the bundle contains both
  `Resources/Shaders/*.metal` and, when toolchain support exists,
  `Resources/Mesh2SplatMetal.metallib`.
- Keep pipeline initialization failures wired to `sourceDescription()` so stale
  metallib, default-library, and runtime-source failures are distinguishable in
  renderer diagnostics.
- If shader sources move to shared includes, update the runtime source
  concatenation path first; it currently reads whole `.metal` files and injects
  `#line` markers.
- Consider exposing `functionCount()` and `sourceKindName()` in debug UI or logs
  for quick verification of which shader path was active.

## Risks And Checks

- Runtime source concatenation can break if multiple `.metal` files define the
  same structs or helper functions. The current shader set must stay compatible
  with whole-file concatenation until includes/metallib are the only path.
- `newDefaultLibrary` is a fallback only; relying on it can mask a missing app
  bundle metallib during local runs.
- `compileSource()` pins `MTLLanguageVersion3_1`. Shader changes that require a
  newer language version need a deliberate compatibility check.
- Function name diagnostics depend on `MTLLibrary.functionNames`; private or
  specialized functions will not appear in the available-name list.
