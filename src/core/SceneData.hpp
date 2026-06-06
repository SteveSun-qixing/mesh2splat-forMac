#pragma once

#include "MeshData.hpp"

#include <algorithm>
#include <cstddef>
#include <string>
#include <vector>

namespace mesh2splat::core {

struct SceneData {
    std::string name;
    std::vector<MeshData> meshes;
    MeshBounds bounds;

    bool empty() const
    {
        return meshes.empty();
    }

    std::size_t meshCount() const
    {
        return meshes.size();
    }

    std::size_t totalVertexCount() const
    {
        std::size_t total = 0;
        for (const MeshData& mesh : meshes) {
            total += mesh.vertices.size();
        }
        return total;
    }

    std::size_t totalDrawRangeCount() const
    {
        std::size_t total = 0;
        for (const MeshData& mesh : meshes) {
            total += mesh.drawRanges.size();
        }
        return total;
    }

    std::size_t totalMaterialCount() const
    {
        std::size_t total = 0;
        for (const MeshData& mesh : meshes) {
            total += mesh.materials.size();
        }
        return total;
    }

    void clear()
    {
        name.clear();
        meshes.clear();
        bounds = {};
    }
};

inline MeshBounds aggregateSceneBounds(const std::vector<MeshData>& meshes)
{
    MeshBounds bounds;
    bool hasBounds = false;
    for (const MeshData& mesh : meshes) {
        if (mesh.empty()) {
            continue;
        }

        if (!hasBounds) {
            bounds = mesh.bounds;
            hasBounds = true;
            continue;
        }

        for (int axis = 0; axis < 3; ++axis) {
            bounds.min[axis] = std::min(bounds.min[axis], mesh.bounds.min[axis]);
            bounds.max[axis] = std::max(bounds.max[axis], mesh.bounds.max[axis]);
        }
    }

    return bounds;
}

inline MeshBounds aggregateSceneBounds(const SceneData& scene)
{
    return aggregateSceneBounds(scene.meshes);
}

} // namespace mesh2splat::core
