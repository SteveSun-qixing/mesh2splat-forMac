#pragma once

#include "FrameData.hpp"
#include "GaussianData.hpp"
#include "MeshData.hpp"

#include <cstddef>
#include <type_traits>

namespace mesh2splat::core::gpu_layout {

constexpr std::size_t kFloat4AlignmentBytes = 16;
constexpr std::size_t kFloat4StrideBytes = sizeof(float) * 4;
constexpr std::size_t kMeshVertexAbiFloatCount = kMeshVertexFloatCount;
constexpr std::size_t kMeshVertexAbiStrideBytes = kMeshVertexStrideBytes;
constexpr std::size_t kGaussianRecordAbiSlotCount = kGaussianRecordSlotCount;
constexpr std::size_t kGaussianRecordAbiStrideBytes = kGaussianRecordStrideBytes;
constexpr std::size_t kMeshGpuMaterialAbiStrideBytes = kMeshGpuMaterialStrideBytes;
constexpr std::size_t kMeshGpuDrawRangeAbiStrideBytes = kMeshGpuDrawRangeStrideBytes;

static_assert(kFloat4StrideBytes == kFloat4AlignmentBytes, "GPU float4 slot assumptions must stay 16 bytes.");

static_assert(std::is_standard_layout<FrameUniforms>::value, "FrameUniforms GPU ABI must remain standard-layout.");
static_assert(alignof(FrameUniforms) == kFloat4AlignmentBytes, "FrameUniforms must remain 16-byte aligned.");
static_assert(sizeof(FrameUniforms) % kFloat4AlignmentBytes == 0, "FrameUniforms must remain 16-byte sized.");

static_assert(std::is_standard_layout<MeshVertex>::value, "MeshVertex GPU ABI must remain standard-layout.");
static_assert(sizeof(MeshVertex) == sizeof(float) * kMeshVertexAbiFloatCount, "MeshVertex GPU ABI must remain 17 floats.");
static_assert(kMeshVertexPositionOffsetBytes == 0, "MeshVertex position must start at float slot 0.");
static_assert(kMeshVertexNormalOffsetBytes == sizeof(float) * 3, "MeshVertex normal must start at float slot 3.");
static_assert(kMeshVertexTangentOffsetBytes == sizeof(float) * 6, "MeshVertex tangent must start at float slot 6.");
static_assert(kMeshVertexUvOffsetBytes == sizeof(float) * 10, "MeshVertex UV must start at float slot 10.");
static_assert(kMeshVertexNormalizedUvOffsetBytes == sizeof(float) * 12, "MeshVertex normalized UV must start at float slot 12.");
static_assert(kMeshVertexScaleOffsetBytes == sizeof(float) * 14, "MeshVertex scale must start at float slot 14.");

static_assert(std::is_standard_layout<MeshGpuMaterialRecord>::value, "MeshGpuMaterialRecord GPU ABI must remain standard-layout.");
static_assert(alignof(MeshGpuMaterialRecord) == kFloat4AlignmentBytes, "MeshGpuMaterialRecord must remain float4 aligned.");
static_assert(sizeof(MeshGpuMaterialRecord) == kFloat4StrideBytes * 3, "MeshGpuMaterialRecord must remain three float4 slots.");
static_assert(kMeshGpuMaterialBaseColorOffsetBytes == 0, "MeshGpuMaterialRecord base color must start at float4 slot 0.");
static_assert(kMeshGpuMaterialEmissiveOffsetBytes == kFloat4StrideBytes, "MeshGpuMaterialRecord emissive must start at float4 slot 1.");
static_assert(kMeshGpuMaterialMetallicOffsetBytes == kFloat4StrideBytes * 2, "MeshGpuMaterialRecord metallic factor must start after two float4 slots.");

static_assert(std::is_standard_layout<MeshGpuDrawRangeRecord>::value, "MeshGpuDrawRangeRecord GPU ABI must remain standard-layout.");
static_assert(alignof(MeshGpuDrawRangeRecord) == kFloat4AlignmentBytes, "MeshGpuDrawRangeRecord must remain float4 aligned.");
static_assert(sizeof(MeshGpuDrawRangeRecord) == kFloat4StrideBytes, "MeshGpuDrawRangeRecord must remain one float4 slot.");

static_assert(std::is_standard_layout<GaussianRecord>::value, "GaussianRecord GPU ABI must remain standard-layout.");
static_assert(sizeof(GaussianRecord) == kFloat4StrideBytes * kGaussianRecordAbiSlotCount, "GaussianRecord must remain six float4 slots.");
static_assert(kGaussianRecordPositionOffsetBytes == 0, "Gaussian position must start at float4 slot 0.");
static_assert(kGaussianRecordColorOffsetBytes == kFloat4StrideBytes, "Gaussian color must start at float4 slot 1.");
static_assert(kGaussianRecordScaleOffsetBytes == kFloat4StrideBytes * 2, "Gaussian scale must start at float4 slot 2.");
static_assert(kGaussianRecordNormalOffsetBytes == kFloat4StrideBytes * 3, "Gaussian normal must start at float4 slot 3.");
static_assert(kGaussianRecordRotationOffsetBytes == kFloat4StrideBytes * 4, "Gaussian rotation must start at float4 slot 4.");
static_assert(kGaussianRecordPbrOffsetBytes == kFloat4StrideBytes * 5, "Gaussian PBR must start at float4 slot 5.");

} // namespace mesh2splat::core::gpu_layout
