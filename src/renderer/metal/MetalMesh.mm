#include "MetalMesh.hpp"

#include "MetalBuffer.hpp"
#include "MetalDeviceContext.hpp"

#include <algorithm>
#include <limits>
#include <string>
#include <utility>
#include <vector>

namespace mesh2splat::metal {
namespace {

MetalMeshMaterial toMetalMaterial(const core::MeshMaterial& material)
{
    MetalMeshMaterial metalMaterial;
    std::copy(std::begin(material.baseColorFactor), std::end(material.baseColorFactor), std::begin(metalMaterial.baseColorFactor));
    std::copy(std::begin(material.emissiveFactor), std::end(material.emissiveFactor), std::begin(metalMaterial.emissiveFactor));
    metalMaterial.metallicFactor = material.metallicFactor;
    metalMaterial.roughnessFactor = material.roughnessFactor;
    metalMaterial.occlusionStrength = material.occlusionStrength;
    metalMaterial.normalScale = material.normalScale;
    return metalMaterial;
}

bool canFitUInt32(std::size_t value)
{
    return value <= static_cast<std::size_t>(std::numeric_limits<uint32_t>::max());
}

} // namespace

struct MetalMesh::Impl {
    MetalDeviceContext* deviceContext = nullptr;
    std::unique_ptr<MetalBuffer> vertexBuffer;
    std::unique_ptr<MetalBuffer> drawRangeBuffer;
    std::unique_ptr<MetalBuffer> materialBuffer;
    std::size_t vertexCount = 0;
    uint32_t drawRangeCount = 0;
    uint32_t materialCount = 0;
};

MetalMesh::MetalMesh(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->deviceContext = &deviceContext;
}

MetalMesh::~MetalMesh() = default;

MetalMesh::MetalMesh(MetalMesh&&) noexcept = default;

MetalMesh& MetalMesh::operator=(MetalMesh&&) noexcept = default;

bool MetalMesh::upload(const core::MeshData& meshData, const char* label)
{
    if (m_impl->deviceContext == nullptr || meshData.vertices.empty() || !canFitUInt32(meshData.vertices.size())) {
        return false;
    }

    std::vector<MetalMeshDrawRange> drawRanges;
    if (meshData.drawRanges.empty()) {
        drawRanges.push_back(MetalMeshDrawRange{
            0,
            static_cast<uint32_t>(meshData.vertices.size()),
            0,
            0,
        });
    } else {
        drawRanges.reserve(meshData.drawRanges.size());
        for (const core::MeshDrawRange& range : meshData.drawRanges) {
            if (range.vertexCount == 0 ||
                range.vertexOffset > meshData.vertices.size() ||
                range.vertexCount > meshData.vertices.size() - range.vertexOffset) {
                return false;
            }

            drawRanges.push_back(MetalMeshDrawRange{
                range.vertexOffset,
                range.vertexCount,
                range.materialIndex,
                0,
            });
        }
    }

    if (!canFitUInt32(drawRanges.size())) {
        return false;
    }

    std::vector<MetalMeshMaterial> materials;
    if (meshData.materials.empty()) {
        materials.push_back(MetalMeshMaterial{});
    } else {
        if (!canFitUInt32(meshData.materials.size())) {
            return false;
        }

        materials.reserve(meshData.materials.size());
        for (const core::MeshMaterial& material : meshData.materials) {
            materials.push_back(toMetalMaterial(material));
        }
    }

    for (const MetalMeshDrawRange& range : drawRanges) {
        if (range.materialIndex >= materials.size()) {
            return false;
        }
    }

    const std::string baseLabel = label != nullptr ? label : (meshData.name.empty() ? "MetalMesh" : meshData.name);
    auto vertexBuffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    auto drawRangeBuffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);
    auto materialBuffer = std::make_unique<MetalBuffer>(*m_impl->deviceContext);

    const std::string vertexLabel = baseLabel + " Vertices";
    const std::string drawRangeLabel = baseLabel + " Draw Ranges";
    const std::string materialLabel = baseLabel + " Materials";

    if (!vertexBuffer->createShared(
            meshData.vertices.size() * sizeof(core::MeshVertex),
            meshData.vertices.data(),
            vertexLabel.c_str()) ||
        !drawRangeBuffer->createShared(
            drawRanges.size() * sizeof(MetalMeshDrawRange),
            drawRanges.data(),
            drawRangeLabel.c_str()) ||
        !materialBuffer->createShared(
            materials.size() * sizeof(MetalMeshMaterial),
            materials.data(),
            materialLabel.c_str())) {
        return false;
    }

    m_impl->vertexBuffer = std::move(vertexBuffer);
    m_impl->drawRangeBuffer = std::move(drawRangeBuffer);
    m_impl->materialBuffer = std::move(materialBuffer);
    m_impl->vertexCount = meshData.vertices.size();
    m_impl->drawRangeCount = static_cast<uint32_t>(drawRanges.size());
    m_impl->materialCount = static_cast<uint32_t>(materials.size());
    return true;
}

void MetalMesh::reset()
{
    m_impl->vertexBuffer.reset();
    m_impl->drawRangeBuffer.reset();
    m_impl->materialBuffer.reset();
    m_impl->vertexCount = 0;
    m_impl->drawRangeCount = 0;
    m_impl->materialCount = 0;
}

bool MetalMesh::isValid() const
{
    return m_impl->vertexBuffer != nullptr && m_impl->vertexBuffer->isValid() &&
        m_impl->drawRangeBuffer != nullptr && m_impl->drawRangeBuffer->isValid() &&
        m_impl->materialBuffer != nullptr && m_impl->materialBuffer->isValid() &&
        m_impl->vertexCount > 0 && m_impl->drawRangeCount > 0 && m_impl->materialCount > 0;
}

std::size_t MetalMesh::vertexCount() const
{
    return m_impl->vertexCount;
}

uint32_t MetalMesh::drawRangeCount() const
{
    return m_impl->drawRangeCount;
}

uint32_t MetalMesh::materialCount() const
{
    return m_impl->materialCount;
}

void* MetalMesh::vertexBuffer() const
{
    return m_impl->vertexBuffer == nullptr ? nullptr : m_impl->vertexBuffer->nativeBuffer();
}

void* MetalMesh::drawRangeBuffer() const
{
    return m_impl->drawRangeBuffer == nullptr ? nullptr : m_impl->drawRangeBuffer->nativeBuffer();
}

void* MetalMesh::materialBuffer() const
{
    return m_impl->materialBuffer == nullptr ? nullptr : m_impl->materialBuffer->nativeBuffer();
}

} // namespace mesh2splat::metal
