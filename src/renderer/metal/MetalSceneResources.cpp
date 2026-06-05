#include "MetalSceneResources.hpp"

#include "MetalDeviceContext.hpp"

#include <string>
#include <utility>

namespace mesh2splat::metal {

struct MetalSceneResources::Impl {
    MetalDeviceContext* deviceContext = nullptr;
    std::vector<MetalMesh> meshes;
    std::size_t totalVertexCount = 0;
    std::size_t totalDrawRangeCount = 0;
    std::size_t totalMaterialCount = 0;
};

MetalSceneResources::MetalSceneResources(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->deviceContext = &deviceContext;
}

MetalSceneResources::~MetalSceneResources() = default;

MetalSceneResources::MetalSceneResources(MetalSceneResources&&) noexcept = default;

MetalSceneResources& MetalSceneResources::operator=(MetalSceneResources&&) noexcept = default;

bool MetalSceneResources::uploadMeshes(const std::vector<core::MeshData>& meshes)
{
    if (m_impl->deviceContext == nullptr || meshes.empty()) {
        reset();
        return false;
    }

    std::vector<MetalMesh> uploadedMeshes;
    uploadedMeshes.reserve(meshes.size());

    std::size_t vertexCount = 0;
    std::size_t drawRangeCount = 0;
    std::size_t materialCount = 0;

    for (const core::MeshData& meshData : meshes) {
        if (meshData.empty()) {
            continue;
        }

        uploadedMeshes.emplace_back(*m_impl->deviceContext);
        MetalMesh& metalMesh = uploadedMeshes.back();
        const char* label = meshData.name.empty() ? nullptr : meshData.name.c_str();
        if (!metalMesh.upload(meshData, label)) {
            reset();
            return false;
        }

        vertexCount += metalMesh.vertexCount();
        drawRangeCount += metalMesh.drawRangeCount();
        materialCount += metalMesh.materialCount();
    }

    if (uploadedMeshes.empty()) {
        reset();
        return false;
    }

    m_impl->meshes = std::move(uploadedMeshes);
    m_impl->totalVertexCount = vertexCount;
    m_impl->totalDrawRangeCount = drawRangeCount;
    m_impl->totalMaterialCount = materialCount;
    return true;
}

void MetalSceneResources::reset()
{
    m_impl->meshes.clear();
    m_impl->totalVertexCount = 0;
    m_impl->totalDrawRangeCount = 0;
    m_impl->totalMaterialCount = 0;
}

bool MetalSceneResources::isValid() const
{
    if (m_impl->meshes.empty()) {
        return false;
    }

    for (const MetalMesh& mesh : m_impl->meshes) {
        if (!mesh.isValid()) {
            return false;
        }
    }

    return true;
}

std::size_t MetalSceneResources::meshCount() const
{
    return m_impl->meshes.size();
}

std::size_t MetalSceneResources::totalVertexCount() const
{
    return m_impl->totalVertexCount;
}

std::size_t MetalSceneResources::totalDrawRangeCount() const
{
    return m_impl->totalDrawRangeCount;
}

std::size_t MetalSceneResources::totalMaterialCount() const
{
    return m_impl->totalMaterialCount;
}

const MetalMesh* MetalSceneResources::meshAt(std::size_t index) const
{
    return index < m_impl->meshes.size() ? &m_impl->meshes[index] : nullptr;
}

MetalMesh* MetalSceneResources::meshAt(std::size_t index)
{
    return index < m_impl->meshes.size() ? &m_impl->meshes[index] : nullptr;
}

} // namespace mesh2splat::metal
