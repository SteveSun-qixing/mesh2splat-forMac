#pragma once

#include "core/SceneData.hpp"

#include <string>
#include <vector>

namespace mesh2splat::io {

struct GltfSceneLoadResult {
    core::SceneData scene;
    std::string warning;
    std::string error;
};

bool loadGltfScene(const std::string& filePath, GltfSceneLoadResult& result);

} // namespace mesh2splat::io
