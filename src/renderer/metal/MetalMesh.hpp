#pragma once

#include "core/MeshData.hpp"
#include "MetalTexture.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <type_traits>

namespace mesh2splat::metal {

class MetalDeviceContext;

struct MetalMeshMaterial {
    float baseColorFactor[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    float emissiveFactor[4] = {0.0f, 0.0f, 0.0f, 0.0f};
    float metallicFactor = 1.0f;
    float roughnessFactor = 1.0f;
    float occlusionStrength = 1.0f;
    float normalScale = 1.0f;
};

static_assert(std::is_standard_layout<MetalMeshMaterial>::value, "MetalMeshMaterial must remain a plain GPU upload record.");
static_assert(sizeof(MetalMeshMaterial) == 48, "MetalMeshMaterial must match the Metal mesh material shader layout.");

struct MetalMeshDrawRange {
    uint32_t vertexOffset = 0;
    uint32_t vertexCount = 0;
    uint32_t materialIndex = 0;
    float surfaceArea = 0.0f;
};

static_assert(std::is_standard_layout<MetalMeshDrawRange>::value, "MetalMeshDrawRange must remain a plain GPU upload record.");
static_assert(sizeof(MetalMeshDrawRange) == 16, "MetalMeshDrawRange must stay a compact 16-byte metadata record.");

struct MetalMeshTextureDiagnostics {
    std::size_t textureCount = 0;
    std::size_t fallbackTextureCount = 0;
    std::size_t fallbackMaterialCount = 0;
    std::size_t missingTextureReferenceCount = 0;
    std::size_t invalidTextureReferenceCount = 0;
    std::size_t failedTextureUploadCount = 0;
    std::size_t sharedTextureReferenceCount = 0;
};

struct MetalMeshUploadDiagnostics {
    std::size_t drawRangeMaterialFallbackCount = 0;
    MetalMeshTextureDiagnostics baseColor;
    MetalMeshTextureDiagnostics metallicRoughness;
    MetalMeshTextureDiagnostics normal;
    MetalMeshTextureDiagnostics occlusion;
    MetalMeshTextureDiagnostics emissive;
};

enum class MetalMeshUploadStatus {
    NotUploaded,
    Success,
    InvalidDeviceContext,
    EmptyMesh,
    VertexCountOverflow,
    VertexCountNotTriangleList,
    DrawRangeOutOfBounds,
    DrawRangeNotTriangleList,
    DrawRangeCountOverflow,
    MaterialCountOverflow,
    DefaultTextureUploadFailed,
    StaticBufferUploadFailed,
};

class MetalMesh {
public:
    explicit MetalMesh(MetalDeviceContext& deviceContext);
    ~MetalMesh();

    MetalMesh(const MetalMesh&) = delete;
    MetalMesh& operator=(const MetalMesh&) = delete;

    MetalMesh(MetalMesh&&) noexcept;
    MetalMesh& operator=(MetalMesh&&) noexcept;

    bool upload(const core::MeshData& meshData, const char* label = nullptr);
    void reset();

    bool isValid() const;
    std::size_t vertexCount() const;
    std::size_t indexCount() const;
    std::size_t conversionCapacity(uint32_t maxSamplesPerTriangle) const;
    std::size_t sizeBytes() const;
    std::size_t textureCount() const;
    uint32_t drawRangeCount() const;
    uint32_t materialCount() const;
    MetalMeshUploadStatus uploadStatus() const;
    const MetalMeshUploadDiagnostics& uploadDiagnostics() const;
    const MetalMeshDrawRange* drawRange(uint32_t index) const;

    void* vertexBuffer() const;
    void* indexBuffer() const;
    void* drawRangeBuffer() const;
    void* materialBuffer() const;
    void* baseColorTexture(uint32_t materialIndex) const;
    void* metallicRoughnessTexture(uint32_t materialIndex) const;
    void* normalTexture(uint32_t materialIndex) const;
    void* occlusionTexture(uint32_t materialIndex) const;
    void* emissiveTexture(uint32_t materialIndex) const;

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
