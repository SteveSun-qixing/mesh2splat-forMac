#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace mesh2splat::core {

struct MeshVertex {
    float position[3] = {0.0f, 0.0f, 0.0f};
    float normal[3] = {0.0f, 1.0f, 0.0f};
    float tangent[4] = {1.0f, 0.0f, 0.0f, 1.0f};
    float uv[2] = {0.0f, 0.0f};
    float normalizedUv[2] = {0.0f, 0.0f};
    float scale[3] = {1.0f, 1.0f, 1.0f};
};

static_assert(sizeof(MeshVertex) == sizeof(float) * 17, "MeshVertex must match the legacy 17-float mesh layout.");

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

struct MeshDrawRange {
    uint32_t vertexOffset = 0;
    uint32_t vertexCount = 0;
    uint32_t materialIndex = 0;
    float surfaceArea = 0.0f;
};

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

} // namespace mesh2splat::core
