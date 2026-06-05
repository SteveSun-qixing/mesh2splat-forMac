#pragma once

#include "core/MeshData.hpp"
#include "MetalMesh.hpp"

#include <cstddef>
#include <memory>
#include <vector>

namespace mesh2splat::metal {

class MetalDeviceContext;

class MetalSceneResources {
public:
    explicit MetalSceneResources(MetalDeviceContext& deviceContext);
    ~MetalSceneResources();

    MetalSceneResources(const MetalSceneResources&) = delete;
    MetalSceneResources& operator=(const MetalSceneResources&) = delete;

    MetalSceneResources(MetalSceneResources&&) noexcept;
    MetalSceneResources& operator=(MetalSceneResources&&) noexcept;

    bool uploadMeshes(const std::vector<core::MeshData>& meshes);
    void reset();

    bool isValid() const;
    std::size_t meshCount() const;
    std::size_t totalVertexCount() const;
    std::size_t totalDrawRangeCount() const;
    std::size_t totalMaterialCount() const;

    const MetalMesh* meshAt(std::size_t index) const;
    MetalMesh* meshAt(std::size_t index);

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
