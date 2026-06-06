#pragma once

#include "FrameData.hpp"
#include "GaussianData.hpp"
#include "MeshData.hpp"

#include <cstddef>

namespace mesh2splat::core::gpu_layout {

static_assert(sizeof(MeshVertex) == sizeof(float) * 17, "MeshVertex GPU ABI must remain 17 floats.");
static_assert(sizeof(FrameUniforms) % 16 == 0, "FrameUniforms must remain 16-byte aligned.");
static_assert(sizeof(GaussianRecord) == sizeof(float) * 4 * 6, "GaussianRecord must remain six float4 slots.");
static_assert(offsetof(GaussianRecord, position) == 0, "Gaussian position must start at float4 slot 0.");
static_assert(offsetof(GaussianRecord, color) == sizeof(float) * 4, "Gaussian color must start at float4 slot 1.");
static_assert(offsetof(GaussianRecord, scale) == sizeof(float) * 4 * 2, "Gaussian scale must start at float4 slot 2.");
static_assert(offsetof(GaussianRecord, normal) == sizeof(float) * 4 * 3, "Gaussian normal must start at float4 slot 3.");
static_assert(offsetof(GaussianRecord, rotation) == sizeof(float) * 4 * 4, "Gaussian rotation must start at float4 slot 4.");
static_assert(offsetof(GaussianRecord, pbr) == sizeof(float) * 4 * 5, "Gaussian PBR must start at float4 slot 5.");

} // namespace mesh2splat::core::gpu_layout
