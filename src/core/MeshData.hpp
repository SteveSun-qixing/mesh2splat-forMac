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
};

struct MeshDrawRange {
    uint32_t vertexOffset = 0;
    uint32_t vertexCount = 0;
    uint32_t materialIndex = 0;
};

struct MeshBounds {
    float min[3] = {0.0f, 0.0f, 0.0f};
    float max[3] = {0.0f, 0.0f, 0.0f};
};

struct MeshData {
    std::string name;
    std::vector<MeshVertex> vertices;
    std::vector<MeshDrawRange> drawRanges;
    std::vector<MeshMaterial> materials;
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
        bounds = {};
        surfaceArea = 0.0f;
    }
};

} // namespace mesh2splat::core
