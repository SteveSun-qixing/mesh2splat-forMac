#pragma once

#include "core/MeshData.hpp"
#include "MetalTexture.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>

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

struct MetalMeshDrawRange {
    uint32_t vertexOffset = 0;
    uint32_t vertexCount = 0;
    uint32_t materialIndex = 0;
    float surfaceArea = 0.0f;
};

static_assert(sizeof(MetalMeshDrawRange) == 16, "MetalMeshDrawRange must stay a compact 16-byte metadata record.");

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
    std::size_t conversionCapacity(uint32_t maxSamplesPerTriangle) const;
    uint32_t drawRangeCount() const;
    uint32_t materialCount() const;
    const MetalMeshDrawRange* drawRange(uint32_t index) const;

    void* vertexBuffer() const;
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
