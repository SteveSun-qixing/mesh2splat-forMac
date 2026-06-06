#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <string>
#include <type_traits>
#include <vector>

namespace mesh2splat::core {

constexpr std::size_t kMeshVertexPositionFloatCount = 3;
constexpr std::size_t kMeshVertexNormalFloatCount = 3;
constexpr std::size_t kMeshVertexTangentFloatCount = 4;
constexpr std::size_t kMeshVertexUvFloatCount = 2;
constexpr std::size_t kMeshVertexNormalizedUvFloatCount = 2;
constexpr std::size_t kMeshVertexScaleFloatCount = 3;
constexpr std::size_t kMeshVertexFloatCount =
    kMeshVertexPositionFloatCount +
    kMeshVertexNormalFloatCount +
    kMeshVertexTangentFloatCount +
    kMeshVertexUvFloatCount +
    kMeshVertexNormalizedUvFloatCount +
    kMeshVertexScaleFloatCount;
constexpr std::size_t kMeshTriangleVertexCount = 3;
constexpr std::size_t kGpuFloat4AlignmentBytes = 16;

struct MeshVertex {
    float position[3] = {0.0f, 0.0f, 0.0f};
    float normal[3] = {0.0f, 1.0f, 0.0f};
    float tangent[4] = {1.0f, 0.0f, 0.0f, 1.0f};
    float uv[2] = {0.0f, 0.0f};
    float normalizedUv[2] = {0.0f, 0.0f};
    float scale[3] = {1.0f, 1.0f, 1.0f};
};

constexpr std::size_t kMeshVertexStrideBytes = sizeof(MeshVertex);
constexpr std::size_t kMeshVertexPositionOffsetBytes = offsetof(MeshVertex, position);
constexpr std::size_t kMeshVertexNormalOffsetBytes = offsetof(MeshVertex, normal);
constexpr std::size_t kMeshVertexTangentOffsetBytes = offsetof(MeshVertex, tangent);
constexpr std::size_t kMeshVertexUvOffsetBytes = offsetof(MeshVertex, uv);
constexpr std::size_t kMeshVertexNormalizedUvOffsetBytes = offsetof(MeshVertex, normalizedUv);
constexpr std::size_t kMeshVertexScaleOffsetBytes = offsetof(MeshVertex, scale);

static_assert(std::is_standard_layout<MeshVertex>::value, "MeshVertex must remain a plain GPU upload record.");
static_assert(sizeof(MeshVertex) == sizeof(float) * kMeshVertexFloatCount, "MeshVertex must match the legacy 17-float mesh layout.");
static_assert(kMeshVertexPositionOffsetBytes == 0, "MeshVertex position must start at float slot 0.");
static_assert(kMeshVertexNormalOffsetBytes == sizeof(float) * 3, "MeshVertex normal must start at float slot 3.");
static_assert(kMeshVertexTangentOffsetBytes == sizeof(float) * 6, "MeshVertex tangent must start at float slot 6.");
static_assert(kMeshVertexUvOffsetBytes == sizeof(float) * 10, "MeshVertex uv must start at float slot 10.");
static_assert(kMeshVertexNormalizedUvOffsetBytes == sizeof(float) * 12, "MeshVertex normalizedUv must start at float slot 12.");
static_assert(kMeshVertexScaleOffsetBytes == sizeof(float) * 14, "MeshVertex scale must start at float slot 14.");

struct MeshMaterial {
    float baseColorFactor[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    float emissiveFactor[3] = {0.0f, 0.0f, 0.0f};
    float metallicFactor = 1.0f;
    float roughnessFactor = 1.0f;
    float occlusionStrength = 1.0f;
    float normalScale = 1.0f;
    int32_t baseColorTextureIndex = -1;
    int32_t metallicRoughnessTextureIndex = -1;
    int32_t normalTextureIndex = -1;
    int32_t occlusionTextureIndex = -1;
    int32_t emissiveTextureIndex = -1;
};

struct alignas(16) MeshGpuMaterialRecord {
    float baseColorFactor[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    float emissiveFactor[4] = {0.0f, 0.0f, 0.0f, 0.0f};
    float metallicFactor = 1.0f;
    float roughnessFactor = 1.0f;
    float occlusionStrength = 1.0f;
    float normalScale = 1.0f;
};

constexpr std::size_t kMeshGpuMaterialStrideBytes = sizeof(MeshGpuMaterialRecord);
constexpr std::size_t kMeshGpuMaterialBaseColorOffsetBytes = offsetof(MeshGpuMaterialRecord, baseColorFactor);
constexpr std::size_t kMeshGpuMaterialEmissiveOffsetBytes = offsetof(MeshGpuMaterialRecord, emissiveFactor);
constexpr std::size_t kMeshGpuMaterialMetallicOffsetBytes = offsetof(MeshGpuMaterialRecord, metallicFactor);
constexpr std::size_t kMeshGpuMaterialRoughnessOffsetBytes = offsetof(MeshGpuMaterialRecord, roughnessFactor);
constexpr std::size_t kMeshGpuMaterialOcclusionOffsetBytes = offsetof(MeshGpuMaterialRecord, occlusionStrength);
constexpr std::size_t kMeshGpuMaterialNormalScaleOffsetBytes = offsetof(MeshGpuMaterialRecord, normalScale);

static_assert(std::is_standard_layout<MeshGpuMaterialRecord>::value, "MeshGpuMaterialRecord must remain a plain GPU upload record.");
static_assert(sizeof(MeshGpuMaterialRecord) == 48, "MeshGpuMaterialRecord must match the MSL MeshMaterial layout.");
static_assert(kMeshGpuMaterialStrideBytes % kGpuFloat4AlignmentBytes == 0, "MeshGpuMaterialRecord stride must remain float4 aligned.");
static_assert(kMeshGpuMaterialBaseColorOffsetBytes == 0, "MeshGpuMaterialRecord base color must start at float4 slot 0.");
static_assert(kMeshGpuMaterialEmissiveOffsetBytes == sizeof(float) * 4, "MeshGpuMaterialRecord emissive must start at float4 slot 1.");
static_assert(kMeshGpuMaterialMetallicOffsetBytes == sizeof(float) * 8, "MeshGpuMaterialRecord metallic factor must follow two float4 slots.");
static_assert(kMeshGpuMaterialRoughnessOffsetBytes == sizeof(float) * 9, "MeshGpuMaterialRecord roughness factor offset changed.");
static_assert(kMeshGpuMaterialOcclusionOffsetBytes == sizeof(float) * 10, "MeshGpuMaterialRecord occlusion strength offset changed.");
static_assert(kMeshGpuMaterialNormalScaleOffsetBytes == sizeof(float) * 11, "MeshGpuMaterialRecord normal scale offset changed.");

struct MeshDrawRange {
    uint32_t vertexOffset = 0;
    uint32_t vertexCount = 0;
    uint32_t materialIndex = 0;
    float surfaceArea = 0.0f;
};

struct alignas(16) MeshGpuDrawRangeRecord {
    uint32_t vertexOffset = 0;
    uint32_t vertexCount = 0;
    uint32_t materialIndex = 0;
    float surfaceArea = 0.0f;
};

constexpr std::size_t kMeshGpuDrawRangeStrideBytes = sizeof(MeshGpuDrawRangeRecord);

static_assert(std::is_standard_layout<MeshGpuDrawRangeRecord>::value, "MeshGpuDrawRangeRecord must remain a plain GPU upload record.");
static_assert(sizeof(MeshGpuDrawRangeRecord) == 16, "MeshGpuDrawRangeRecord must stay a compact 16-byte metadata record.");
static_assert(kMeshGpuDrawRangeStrideBytes % kGpuFloat4AlignmentBytes == 0, "MeshGpuDrawRangeRecord stride must remain float4 aligned.");
static_assert(offsetof(MeshGpuDrawRangeRecord, vertexOffset) == 0, "MeshGpuDrawRangeRecord vertexOffset offset changed.");
static_assert(offsetof(MeshGpuDrawRangeRecord, vertexCount) == sizeof(uint32_t), "MeshGpuDrawRangeRecord vertexCount offset changed.");
static_assert(offsetof(MeshGpuDrawRangeRecord, materialIndex) == sizeof(uint32_t) * 2, "MeshGpuDrawRangeRecord materialIndex offset changed.");
static_assert(offsetof(MeshGpuDrawRangeRecord, surfaceArea) == sizeof(uint32_t) * 3, "MeshGpuDrawRangeRecord surfaceArea offset changed.");

struct MeshBounds {
    float min[3] = {0.0f, 0.0f, 0.0f};
    float max[3] = {0.0f, 0.0f, 0.0f};
};

struct MeshImageData {
    std::string name;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t channels = 4;
    std::vector<uint8_t> rgba8;
};

struct MeshData {
    std::string name;
    std::vector<MeshVertex> vertices;
    std::vector<MeshDrawRange> drawRanges;
    std::vector<MeshMaterial> materials;
    std::vector<MeshImageData> images;
    MeshBounds bounds;
    float surfaceArea = 0.0f;

    bool empty() const
    {
        return vertices.empty();
    }

    std::size_t vertexCount() const
    {
        return vertices.size();
    }

    void clear()
    {
        name.clear();
        vertices.clear();
        drawRanges.clear();
        materials.clear();
        images.clear();
        bounds = {};
        surfaceArea = 0.0f;
    }
};

inline bool meshCountFitsUInt32(std::size_t count)
{
    return count <= static_cast<std::size_t>(std::numeric_limits<uint32_t>::max());
}

inline bool meshVertexCountFitsBuffer(std::size_t count)
{
    return meshCountFitsUInt32(count) &&
        count <= std::numeric_limits<std::size_t>::max() / sizeof(MeshVertex);
}

inline std::size_t meshVertexBufferByteSize(std::size_t count)
{
    return meshVertexCountFitsBuffer(count) ? count * sizeof(MeshVertex) : 0;
}

inline bool meshMaterialCountFitsBuffer(std::size_t count)
{
    return meshCountFitsUInt32(count) &&
        count <= std::numeric_limits<std::size_t>::max() / sizeof(MeshGpuMaterialRecord);
}

inline std::size_t meshGpuMaterialBufferByteSize(std::size_t count)
{
    return meshMaterialCountFitsBuffer(count) ? count * sizeof(MeshGpuMaterialRecord) : 0;
}

inline bool meshDrawRangeCountFitsBuffer(std::size_t count)
{
    return meshCountFitsUInt32(count) &&
        count <= std::numeric_limits<std::size_t>::max() / sizeof(MeshGpuDrawRangeRecord);
}

inline std::size_t meshGpuDrawRangeBufferByteSize(std::size_t count)
{
    return meshDrawRangeCountFitsBuffer(count) ? count * sizeof(MeshGpuDrawRangeRecord) : 0;
}

inline bool meshVertexCountIsTriangleList(std::size_t vertexCount)
{
    return vertexCount > 0 && vertexCount % kMeshTriangleVertexCount == 0;
}

inline bool isFiniteMeshVertex(const MeshVertex& vertex)
{
    const float* values[] = {
        vertex.position,
        vertex.normal,
        vertex.tangent,
        vertex.uv,
        vertex.normalizedUv,
        vertex.scale,
    };
    const std::size_t counts[] = {
        kMeshVertexPositionFloatCount,
        kMeshVertexNormalFloatCount,
        kMeshVertexTangentFloatCount,
        kMeshVertexUvFloatCount,
        kMeshVertexNormalizedUvFloatCount,
        kMeshVertexScaleFloatCount,
    };

    for (std::size_t slot = 0; slot < sizeof(values) / sizeof(values[0]); ++slot) {
        for (std::size_t component = 0; component < counts[slot]; ++component) {
            if (!std::isfinite(values[slot][component])) {
                return false;
            }
        }
    }
    return true;
}

inline bool isFiniteMeshMaterial(const MeshMaterial& material)
{
    for (float value : material.baseColorFactor) {
        if (!std::isfinite(value)) {
            return false;
        }
    }
    for (float value : material.emissiveFactor) {
        if (!std::isfinite(value)) {
            return false;
        }
    }
    return std::isfinite(material.metallicFactor) &&
        std::isfinite(material.roughnessFactor) &&
        std::isfinite(material.occlusionStrength) &&
        std::isfinite(material.normalScale);
}

inline bool isValidMeshDrawRangeForGpuUpload(
    const MeshDrawRange& range,
    std::size_t totalVertexCount,
    std::size_t materialCount)
{
    if (range.vertexCount == 0 ||
        range.vertexOffset > totalVertexCount ||
        range.vertexCount > totalVertexCount - range.vertexOffset ||
        range.vertexOffset % kMeshTriangleVertexCount != 0 ||
        range.vertexCount % kMeshTriangleVertexCount != 0 ||
        !std::isfinite(range.surfaceArea)) {
        return false;
    }

    return materialCount == 0 || range.materialIndex < materialCount;
}

inline bool isValidMeshDataForGpuUpload(const MeshData& mesh)
{
    if (!meshVertexCountFitsBuffer(mesh.vertices.size()) ||
        !meshVertexCountIsTriangleList(mesh.vertices.size()) ||
        !meshMaterialCountFitsBuffer(mesh.materials.empty() ? 1 : mesh.materials.size()) ||
        !meshDrawRangeCountFitsBuffer(mesh.drawRanges.empty() ? 1 : mesh.drawRanges.size()) ||
        !std::isfinite(mesh.surfaceArea)) {
        return false;
    }

    for (const MeshVertex& vertex : mesh.vertices) {
        if (!isFiniteMeshVertex(vertex)) {
            return false;
        }
    }
    for (const MeshMaterial& material : mesh.materials) {
        if (!isFiniteMeshMaterial(material)) {
            return false;
        }
    }
    for (const MeshDrawRange& range : mesh.drawRanges) {
        if (!isValidMeshDrawRangeForGpuUpload(range, mesh.vertices.size(), mesh.materials.size())) {
            return false;
        }
    }
    return true;
}

inline void copyMeshComponents(float* destination, const float* source, std::size_t count)
{
    if (destination == nullptr || source == nullptr) {
        return;
    }

    std::copy_n(source, count, destination);
}

inline MeshVertex makeMeshVertex(
    const float* position3,
    const float* normal3 = nullptr,
    const float* tangent4 = nullptr,
    const float* uv2 = nullptr,
    const float* normalizedUv2 = nullptr,
    const float* scale3 = nullptr)
{
    MeshVertex vertex;
    copyMeshComponents(vertex.position, position3, kMeshVertexPositionFloatCount);
    copyMeshComponents(vertex.normal, normal3, kMeshVertexNormalFloatCount);
    copyMeshComponents(vertex.tangent, tangent4, kMeshVertexTangentFloatCount);
    copyMeshComponents(vertex.uv, uv2, kMeshVertexUvFloatCount);
    copyMeshComponents(vertex.normalizedUv, normalizedUv2, kMeshVertexNormalizedUvFloatCount);
    copyMeshComponents(vertex.scale, scale3, kMeshVertexScaleFloatCount);
    return vertex;
}

inline MeshGpuMaterialRecord makeMeshGpuMaterialRecord(const MeshMaterial& material)
{
    MeshGpuMaterialRecord record;
    std::copy_n(material.baseColorFactor, 4, record.baseColorFactor);
    std::copy_n(material.emissiveFactor, 3, record.emissiveFactor);
    record.metallicFactor = material.metallicFactor;
    record.roughnessFactor = material.roughnessFactor;
    record.occlusionStrength = material.occlusionStrength;
    record.normalScale = material.normalScale;
    return record;
}

inline MeshGpuDrawRangeRecord makeMeshGpuDrawRangeRecord(const MeshDrawRange& range, float fallbackSurfaceArea = 0.0f)
{
    MeshGpuDrawRangeRecord record;
    record.vertexOffset = range.vertexOffset;
    record.vertexCount = range.vertexCount;
    record.materialIndex = range.materialIndex;
    record.surfaceArea = range.surfaceArea > 0.0f ? range.surfaceArea : fallbackSurfaceArea;
    return record;
}

inline MeshGpuDrawRangeRecord makeFullMeshGpuDrawRangeRecord(
    std::size_t vertexCount,
    uint32_t materialIndex = 0,
    float surfaceArea = 0.0f)
{
    MeshGpuDrawRangeRecord record;
    record.vertexCount = meshCountFitsUInt32(vertexCount) ? static_cast<uint32_t>(vertexCount) : 0;
    record.materialIndex = materialIndex;
    record.surfaceArea = surfaceArea;
    return record;
}

} // namespace mesh2splat::core
