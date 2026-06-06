#pragma once

#include "core/SceneData.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace mesh2splat::io {

struct GltfSceneLoadStats {
    uint64_t sourceSceneCount = 0;
    uint64_t sourceNodeCount = 0;
    uint64_t sourceMeshCount = 0;
    uint64_t sourceMaterialCount = 0;
    uint64_t sourceTextureCount = 0;
    uint64_t sourceImageCount = 0;
    uint64_t meshInstanceCount = 0;
    uint64_t primitiveCount = 0;
    uint64_t loadedPrimitiveCount = 0;
    uint64_t skippedPrimitiveCount = 0;
    uint64_t loadedMeshCount = 0;
    uint64_t loadedVertexCount = 0;
    uint64_t loadedDrawRangeCount = 0;
    uint64_t loadedMaterialCount = 0;
    uint64_t loadedImageCount = 0;
    uint64_t missingMaterialCount = 0;
    uint64_t invalidMaterialCount = 0;
    uint64_t referencedTextureCount = 0;
    uint64_t missingTextureCount = 0;
    uint64_t invalidTextureCount = 0;
    uint64_t missingNormalCount = 0;
    uint64_t missingTangentCount = 0;
    uint64_t missingUvCount = 0;
    uint64_t generatedIndexCount = 0;
    uint64_t unsupportedPrimitiveModeCount = 0;
    uint64_t missingPositionCount = 0;
    uint64_t invalidAccessorCount = 0;
    uint64_t invalidIndexCount = 0;
    uint64_t invalidNodeReferenceCount = 0;
    uint64_t externalBufferUriCount = 0;
    uint64_t externalImageUriCount = 0;
    uint64_t embeddedBufferCount = 0;
    uint64_t embeddedImageCount = 0;
    bool usedMeshFallbackForEmptyScene = false;
};

struct GltfSceneLoadResult {
    core::SceneData scene;
    std::string warning;
    std::string error;
    GltfSceneLoadStats stats;
    std::vector<std::string> diagnostics;

    bool succeeded() const
    {
        return error.empty() && !scene.empty();
    }
};

bool loadGltfScene(const std::string& filePath, GltfSceneLoadResult& result);

} // namespace mesh2splat::io
