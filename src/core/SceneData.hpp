#pragma once

#include "MeshData.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <string>
#include <utility>
#include <vector>

namespace mesh2splat::core {

constexpr uint32_t kInvalidSceneIndex = std::numeric_limits<uint32_t>::max();

struct SceneTextureRef {
    uint32_t imageIndex = kInvalidSceneIndex;
    std::string name;
    std::string uri;

    bool valid() const
    {
        return imageIndex != kInvalidSceneIndex;
    }
};

struct SceneMaterialRef {
    uint32_t materialIndex = kInvalidSceneIndex;
    int32_t baseColorTextureIndex = -1;
    int32_t metallicRoughnessTextureIndex = -1;
    int32_t normalTextureIndex = -1;
    int32_t occlusionTextureIndex = -1;
    int32_t emissiveTextureIndex = -1;

    bool valid() const
    {
        return materialIndex != kInvalidSceneIndex;
    }
};

struct SceneMeshRef {
    uint32_t meshIndex = kInvalidSceneIndex;
    uint32_t firstMaterialIndex = 0;
    uint32_t materialCount = 0;
    uint32_t firstTextureIndex = 0;
    uint32_t textureCount = 0;
    uint32_t firstDrawRangeIndex = 0;
    uint32_t drawRangeCount = 0;
    uint32_t firstVertexIndex = 0;
    uint32_t vertexCount = 0;
    std::string name;

    bool valid() const
    {
        return meshIndex != kInvalidSceneIndex;
    }
};

struct SceneStatistics {
    std::size_t meshCount = 0;
    std::size_t vertexCount = 0;
    std::size_t drawRangeCount = 0;
    std::size_t materialCount = 0;
    std::size_t textureCount = 0;
    std::size_t gaussianCount = 0;
    float surfaceArea = 0.0f;
    MeshBounds bounds;

    bool empty() const
    {
        return meshCount == 0 && gaussianCount == 0;
    }

    bool hasMeshes() const
    {
        return meshCount != 0 && vertexCount != 0;
    }

    bool hasGaussians() const
    {
        return gaussianCount != 0;
    }

    bool hasRenderableContent() const
    {
        return hasMeshes() || hasGaussians();
    }
};

struct SceneData {
    std::string name;
    std::vector<MeshData> meshes;
    std::vector<MeshMaterial> materials;
    std::vector<MeshImageData> textures;
    std::vector<SceneMaterialRef> materialRefs;
    std::vector<SceneTextureRef> textureRefs;
    std::vector<SceneMeshRef> meshRefs;
    MeshBounds bounds;
    std::size_t gaussianRecordCount = 0;

    bool empty() const
    {
        return meshes.empty() && gaussianRecordCount == 0;
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
        if (!materials.empty()) {
            return materials.size();
        }

        std::size_t total = 0;
        for (const MeshData& mesh : meshes) {
            total += mesh.materials.size();
        }
        return total;
    }

    std::size_t totalTextureCount() const
    {
        if (!textures.empty()) {
            return textures.size();
        }

        std::size_t total = 0;
        for (const MeshData& mesh : meshes) {
            total += mesh.images.size();
        }
        return total;
    }

    std::size_t totalGaussianCount() const
    {
        return gaussianRecordCount;
    }

    float totalSurfaceArea() const
    {
        float total = 0.0f;
        for (const MeshData& mesh : meshes) {
            total += mesh.surfaceArea;
        }
        return total;
    }

    std::size_t vertexCount() const
    {
        return totalVertexCount();
    }

    std::size_t drawRangeCount() const
    {
        return totalDrawRangeCount();
    }

    std::size_t materialCount() const
    {
        return totalMaterialCount();
    }

    std::size_t textureCount() const
    {
        return totalTextureCount();
    }

    std::size_t gaussianCount() const
    {
        return totalGaussianCount();
    }

    bool hasMeshes() const
    {
        return totalVertexCount() != 0;
    }

    bool hasGaussians() const
    {
        return gaussianRecordCount != 0;
    }

    bool hasRenderableContent() const
    {
        return hasMeshes() || hasGaussians();
    }

    void setGaussianCount(std::size_t count)
    {
        gaussianRecordCount = count;
    }

    void rebuildReferences()
    {
        materials.clear();
        textures.clear();
        materialRefs.clear();
        textureRefs.clear();
        meshRefs.clear();

        std::size_t firstVertexIndex = 0;
        std::size_t firstDrawRangeIndex = 0;
        for (std::size_t meshIndex = 0; meshIndex < meshes.size(); ++meshIndex) {
            const MeshData& mesh = meshes[meshIndex];
            const std::size_t firstMaterialIndex = materials.size();
            const std::size_t firstTextureIndex = textures.size();

            materials.insert(materials.end(), mesh.materials.begin(), mesh.materials.end());
            textures.insert(textures.end(), mesh.images.begin(), mesh.images.end());

            for (std::size_t localMaterialIndex = 0; localMaterialIndex < mesh.materials.size(); ++localMaterialIndex) {
                const MeshMaterial& material = mesh.materials[localMaterialIndex];
                SceneMaterialRef materialRef;
                materialRef.materialIndex = checkedSceneIndex(firstMaterialIndex + localMaterialIndex);
                materialRef.baseColorTextureIndex = remapTextureIndex(material.baseColorTextureIndex, firstTextureIndex, mesh.images.size());
                materialRef.metallicRoughnessTextureIndex =
                    remapTextureIndex(material.metallicRoughnessTextureIndex, firstTextureIndex, mesh.images.size());
                materialRef.normalTextureIndex = remapTextureIndex(material.normalTextureIndex, firstTextureIndex, mesh.images.size());
                materialRef.occlusionTextureIndex = remapTextureIndex(material.occlusionTextureIndex, firstTextureIndex, mesh.images.size());
                materialRef.emissiveTextureIndex = remapTextureIndex(material.emissiveTextureIndex, firstTextureIndex, mesh.images.size());
                materialRefs.push_back(materialRef);
            }

            for (std::size_t localTextureIndex = 0; localTextureIndex < mesh.images.size(); ++localTextureIndex) {
                const MeshImageData& image = mesh.images[localTextureIndex];
                SceneTextureRef textureRef;
                textureRef.imageIndex = checkedSceneIndex(firstTextureIndex + localTextureIndex);
                textureRef.name = image.name;
                textureRefs.push_back(std::move(textureRef));
            }

            SceneMeshRef meshRef;
            meshRef.meshIndex = checkedSceneIndex(meshIndex);
            meshRef.firstMaterialIndex = checkedSceneIndex(firstMaterialIndex);
            meshRef.materialCount = checkedSceneIndex(mesh.materials.size());
            meshRef.firstTextureIndex = checkedSceneIndex(firstTextureIndex);
            meshRef.textureCount = checkedSceneIndex(mesh.images.size());
            meshRef.firstDrawRangeIndex = checkedSceneIndex(firstDrawRangeIndex);
            meshRef.drawRangeCount = checkedSceneIndex(mesh.drawRanges.size());
            meshRef.firstVertexIndex = checkedSceneIndex(firstVertexIndex);
            meshRef.vertexCount = checkedSceneIndex(mesh.vertices.size());
            meshRef.name = mesh.name;
            meshRefs.push_back(std::move(meshRef));

            firstVertexIndex += mesh.vertices.size();
            firstDrawRangeIndex += mesh.drawRanges.size();
        }
    }

    SceneStatistics statistics() const
    {
        SceneStatistics stats;
        stats.meshCount = meshCount();
        stats.vertexCount = totalVertexCount();
        stats.drawRangeCount = totalDrawRangeCount();
        stats.materialCount = totalMaterialCount();
        stats.textureCount = totalTextureCount();
        stats.gaussianCount = totalGaussianCount();
        stats.surfaceArea = totalSurfaceArea();
        stats.bounds = bounds;
        return stats;
    }

    void clear()
    {
        name.clear();
        meshes.clear();
        materials.clear();
        textures.clear();
        materialRefs.clear();
        textureRefs.clear();
        meshRefs.clear();
        bounds = {};
        gaussianRecordCount = 0;
    }

private:
    static uint32_t checkedSceneIndex(std::size_t index)
    {
        return meshCountFitsUInt32(index) ? static_cast<uint32_t>(index) : kInvalidSceneIndex;
    }

    static int32_t remapTextureIndex(int32_t localIndex, std::size_t firstTextureIndex, std::size_t textureCount)
    {
        if (localIndex < 0 || static_cast<std::size_t>(localIndex) >= textureCount) {
            return -1;
        }

        const std::size_t sceneIndex = firstTextureIndex + static_cast<std::size_t>(localIndex);
        if (sceneIndex > static_cast<std::size_t>(std::numeric_limits<int32_t>::max())) {
            return -1;
        }
        return static_cast<int32_t>(sceneIndex);
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

inline SceneStatistics sceneStatistics(const SceneData& scene)
{
    return scene.statistics();
}

inline SceneData makeSceneData(std::string name, std::vector<MeshData> meshes, std::size_t gaussianCount = 0)
{
    SceneData scene;
    scene.name = std::move(name);
    scene.meshes = std::move(meshes);
    scene.bounds = aggregateSceneBounds(scene);
    scene.gaussianRecordCount = gaussianCount;
    scene.rebuildReferences();
    return scene;
}

} // namespace mesh2splat::core
