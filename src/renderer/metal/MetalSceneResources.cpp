#include "MetalSceneResources.hpp"

#include "MetalDeviceContext.hpp"

#include <limits>
#include <string>
#include <utility>

namespace mesh2splat::metal {
namespace {

constexpr std::size_t kNoFailedMeshIndex = std::numeric_limits<std::size_t>::max();

void addSaturated(std::size_t& total, std::size_t value)
{
    if (value > std::numeric_limits<std::size_t>::max() - total) {
        total = std::numeric_limits<std::size_t>::max();
        return;
    }

    total += value;
}

void addTextureDiagnostics(
    MetalMeshTextureDiagnostics& total,
    const MetalMeshTextureDiagnostics& value)
{
    addSaturated(total.textureCount, value.textureCount);
    addSaturated(total.fallbackTextureCount, value.fallbackTextureCount);
    addSaturated(total.fallbackMaterialCount, value.fallbackMaterialCount);
    addSaturated(total.missingTextureReferenceCount, value.missingTextureReferenceCount);
    addSaturated(total.invalidTextureReferenceCount, value.invalidTextureReferenceCount);
    addSaturated(total.failedTextureUploadCount, value.failedTextureUploadCount);
    addSaturated(total.sharedTextureReferenceCount, value.sharedTextureReferenceCount);
}

void addUploadDiagnostics(
    MetalMeshUploadDiagnostics& total,
    const MetalMeshUploadDiagnostics& value)
{
    addSaturated(total.drawRangeMaterialFallbackCount, value.drawRangeMaterialFallbackCount);
    addTextureDiagnostics(total.baseColor, value.baseColor);
    addTextureDiagnostics(total.metallicRoughness, value.metallicRoughness);
    addTextureDiagnostics(total.normal, value.normal);
    addTextureDiagnostics(total.occlusion, value.occlusion);
    addTextureDiagnostics(total.emissive, value.emissive);
}

} // namespace

struct MetalSceneResources::Impl {
    MetalDeviceContext* deviceContext = nullptr;
    std::vector<MetalMesh> meshes;
    std::size_t totalVertexCount = 0;
    std::size_t totalIndexCount = 0;
    std::size_t totalDrawRangeCount = 0;
    std::size_t totalMaterialCount = 0;
    std::size_t totalTextureCount = 0;
    MetalSceneResourcesUploadStatus uploadStatus = MetalSceneResourcesUploadStatus::NotUploaded;
    std::size_t skippedEmptyMeshCount = 0;
    std::size_t failedMeshIndex = kNoFailedMeshIndex;
    MetalMeshUploadStatus failedMeshUploadStatus = MetalMeshUploadStatus::NotUploaded;
    MetalMeshUploadDiagnostics uploadDiagnostics;
};

MetalSceneResources::MetalSceneResources(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->deviceContext = &deviceContext;
}

MetalSceneResources::~MetalSceneResources() = default;

MetalSceneResources::MetalSceneResources(MetalSceneResources&&) noexcept = default;

MetalSceneResources& MetalSceneResources::operator=(MetalSceneResources&&) noexcept = default;

bool MetalSceneResources::uploadScene(const core::SceneData& scene)
{
    return uploadMeshes(scene.meshes);
}

bool MetalSceneResources::uploadMeshes(const std::vector<core::MeshData>& meshes)
{
    auto fail = [this](
                    MetalSceneResourcesUploadStatus status,
                    std::size_t skippedEmptyMeshCount = 0,
                    std::size_t failedMeshIndex = kNoFailedMeshIndex,
                    MetalMeshUploadStatus failedMeshUploadStatus = MetalMeshUploadStatus::NotUploaded) {
        reset();
        m_impl->uploadStatus = status;
        m_impl->skippedEmptyMeshCount = skippedEmptyMeshCount;
        m_impl->failedMeshIndex = failedMeshIndex;
        m_impl->failedMeshUploadStatus = failedMeshUploadStatus;
        return false;
    };

    if (m_impl->deviceContext == nullptr) {
        return fail(MetalSceneResourcesUploadStatus::InvalidDeviceContext);
    }
    if (meshes.empty()) {
        return fail(MetalSceneResourcesUploadStatus::EmptyInput);
    }

    std::vector<MetalMesh> uploadedMeshes;
    uploadedMeshes.reserve(meshes.size());

    std::size_t vertexCount = 0;
    std::size_t indexCount = 0;
    std::size_t drawRangeCount = 0;
    std::size_t materialCount = 0;
    std::size_t textureCount = 0;
    std::size_t skippedEmptyMeshCount = 0;
    MetalMeshUploadDiagnostics diagnostics;

    for (std::size_t meshIndex = 0; meshIndex < meshes.size(); ++meshIndex) {
        const core::MeshData& meshData = meshes[meshIndex];
        if (meshData.empty()) {
            addSaturated(skippedEmptyMeshCount, 1);
            continue;
        }

        uploadedMeshes.emplace_back(*m_impl->deviceContext);
        MetalMesh& metalMesh = uploadedMeshes.back();
        const std::string fallbackLabel = "Scene Mesh " + std::to_string(meshIndex);
        const char* label = meshData.name.empty() ? fallbackLabel.c_str() : meshData.name.c_str();
        if (!metalMesh.upload(meshData, label)) {
            return fail(
                MetalSceneResourcesUploadStatus::MeshUploadFailed,
                skippedEmptyMeshCount,
                meshIndex,
                metalMesh.uploadStatus());
        }

        addSaturated(vertexCount, metalMesh.vertexCount());
        addSaturated(indexCount, metalMesh.indexCount());
        addSaturated(drawRangeCount, metalMesh.drawRangeCount());
        addSaturated(materialCount, metalMesh.materialCount());
        addSaturated(textureCount, metalMesh.textureCount());
        addUploadDiagnostics(diagnostics, metalMesh.uploadDiagnostics());
    }

    if (uploadedMeshes.empty()) {
        return fail(MetalSceneResourcesUploadStatus::NoUploadableMeshes, skippedEmptyMeshCount);
    }

    m_impl->meshes = std::move(uploadedMeshes);
    m_impl->totalVertexCount = vertexCount;
    m_impl->totalIndexCount = indexCount;
    m_impl->totalDrawRangeCount = drawRangeCount;
    m_impl->totalMaterialCount = materialCount;
    m_impl->totalTextureCount = textureCount;
    m_impl->uploadStatus = MetalSceneResourcesUploadStatus::Success;
    m_impl->skippedEmptyMeshCount = skippedEmptyMeshCount;
    m_impl->failedMeshIndex = kNoFailedMeshIndex;
    m_impl->failedMeshUploadStatus = MetalMeshUploadStatus::NotUploaded;
    m_impl->uploadDiagnostics = diagnostics;
    return true;
}

void MetalSceneResources::reset()
{
    m_impl->meshes.clear();
    m_impl->totalVertexCount = 0;
    m_impl->totalIndexCount = 0;
    m_impl->totalDrawRangeCount = 0;
    m_impl->totalMaterialCount = 0;
    m_impl->totalTextureCount = 0;
    m_impl->uploadStatus = MetalSceneResourcesUploadStatus::NotUploaded;
    m_impl->skippedEmptyMeshCount = 0;
    m_impl->failedMeshIndex = kNoFailedMeshIndex;
    m_impl->failedMeshUploadStatus = MetalMeshUploadStatus::NotUploaded;
    m_impl->uploadDiagnostics = {};
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

std::size_t MetalSceneResources::totalIndexCount() const
{
    return m_impl->totalIndexCount;
}

std::size_t MetalSceneResources::totalDrawRangeCount() const
{
    return m_impl->totalDrawRangeCount;
}

std::size_t MetalSceneResources::totalMaterialCount() const
{
    return m_impl->totalMaterialCount;
}

std::size_t MetalSceneResources::totalTextureCount() const
{
    return m_impl->totalTextureCount;
}

std::size_t MetalSceneResources::sizeBytes() const
{
    std::size_t total = 0;
    for (const MetalMesh& mesh : m_impl->meshes) {
        const std::size_t meshBytes = mesh.sizeBytes();
        if (meshBytes > std::numeric_limits<std::size_t>::max() - total) {
            return std::numeric_limits<std::size_t>::max();
        }
        total += meshBytes;
    }
    return total;
}

std::size_t MetalSceneResources::conversionCapacity(uint32_t maxSamplesPerTriangle) const
{
    std::size_t capacity = 0;
    for (const MetalMesh& mesh : m_impl->meshes) {
        const std::size_t meshCapacity = mesh.conversionCapacity(maxSamplesPerTriangle);
        if (meshCapacity > std::numeric_limits<std::size_t>::max() - capacity) {
            return std::numeric_limits<std::size_t>::max();
        }
        capacity += meshCapacity;
    }
    return capacity;
}

MetalSceneResourcesUploadStatus MetalSceneResources::uploadStatus() const
{
    return m_impl->uploadStatus;
}

std::size_t MetalSceneResources::skippedEmptyMeshCount() const
{
    return m_impl->skippedEmptyMeshCount;
}

std::size_t MetalSceneResources::failedMeshIndex() const
{
    return m_impl->failedMeshIndex;
}

MetalMeshUploadStatus MetalSceneResources::failedMeshUploadStatus() const
{
    return m_impl->failedMeshUploadStatus;
}

const MetalMeshUploadDiagnostics& MetalSceneResources::uploadDiagnostics() const
{
    return m_impl->uploadDiagnostics;
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
