#pragma once

#include "MeshData.hpp"

#include <string>
#include <vector>

namespace mesh2splat::core {

struct GltfMeshLoadResult {
    std::vector<MeshData> meshes;
    std::string warning;
    std::string error;
};

bool loadGltfMeshData(const std::string& filePath, GltfMeshLoadResult& result);

} // namespace mesh2splat::core
