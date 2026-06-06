// Mesh2Splat GPU layout freeze notes.
//
// This file intentionally does not define shared structs yet. The current runtime
// shader fallback concatenates all bundled .metal files, so duplicate struct
// definitions would break source compilation. The authoritative layout map is in
// docs/gpu-data-layout.md and the C++ static assertions in src/core/GpuTypes.hpp.
//
// When the offline Metal toolchain is available and the shader build moves to
// true MSL includes, this file can become the shared MSL type header.
