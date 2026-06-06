#pragma once

#include "core/SceneData.hpp"
#include "MetalMesh.hpp"

#include <cstddef>
#include <memory>
#include <vector>

namespace mesh2splat::metal {

class MetalDeviceContext;

enum class MetalSceneResourcesUploadStatus {
    NotUploaded,
    Success,
    InvalidDeviceContext,
    EmptyInput,
    NoUploadableMeshes,
    MeshUploadFailed,
};

class MetalSceneResources {
public:
    explicit MetalSceneResources(MetalDeviceContext& deviceContext);
    ~MetalSceneResources();

    MetalSceneResources(const MetalSceneResources&) = delete;
    MetalSceneResources& operator=(const MetalSceneResources&) = delete;

    MetalSceneResources(MetalSceneResources&&) noexcept;
    MetalSceneResources& operator=(MetalSceneResources&&) noexcept;

    bool uploadScene(const core::SceneData& scene);
    bool uploadMeshes(const std::vector<core::MeshData>& meshes);
    void reset();

    bool isValid() const;
    std::size_t meshCount() const;
    std::size_t totalVertexCount() const;
    std::size_t totalIndexCount() const;
    std::size_t totalDrawRangeCount() const;
    std::size_t totalMaterialCount() const;
    std::size_t totalTextureCount() const;
    std::size_t sizeBytes() const;
    std::size_t conversionCapacity(uint32_t maxSamplesPerTriangle) const;
    MetalSceneResourcesUploadStatus uploadStatus() const;
    std::size_t skippedEmptyMeshCount() const;
    std::size_t failedMeshIndex() const;
    MetalMeshUploadStatus failedMeshUploadStatus() const;
    const MetalMeshUploadDiagnostics& uploadDiagnostics() const;

    const MetalMesh* meshAt(std::size_t index) const;
    MetalMesh* meshAt(std::size_t index);

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
