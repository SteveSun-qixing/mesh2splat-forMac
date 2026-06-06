#pragma once

#include "SceneData.hpp"

#include <string>
#include <vector>

namespace mesh2splat::core {

struct GltfMeshLoadResult {
    SceneData scene;
    std::string warning;
    std::string error;
};

bool loadGltfMeshData(const std::string& filePath, GltfMeshLoadResult& result);

} // namespace mesh2splat::core
