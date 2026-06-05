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

bool createDefaultBaseColorTexture(MetalTexture& texture)
{
    const uint8_t whitePixel[4] = {255, 255, 255, 255};
    return texture.create2D(
        1,
        1,
        MetalTextureFormat::RGBA8UnormSrgb,
        MetalTextureUsage::ShaderRead,
        "Default Base Color Texture") &&
        texture.upload2D(whitePixel, sizeof(whitePixel), 1, 1);
}

bool createBaseColorTexture(
    MetalDeviceContext& deviceContext,
    const core::MeshImageData& image,
    const std::string& label,
    std::unique_ptr<MetalTexture>& texture)
{
    if (image.width == 0 || image.height == 0 || image.rgba8.empty()) {
        return false;
    }

    texture = std::make_unique<MetalTexture>(deviceContext);
    return texture->create2D(
        image.width,
        image.height,
        MetalTextureFormat::RGBA8UnormSrgb,
        MetalTextureUsage::ShaderRead,
        label.c_str()) &&
        texture->upload2D(image.rgba8.data(), static_cast<std::size_t>(image.width) * 4, image.width, image.height);
}

} // namespace

struct MetalMesh::Impl {
    MetalDeviceContext* deviceContext = nullptr;
    std::unique_ptr<MetalBuffer> vertexBuffer;
    std::unique_ptr<MetalBuffer> drawRangeBuffer;
    std::unique_ptr<MetalBuffer> materialBuffer;
    std::vector<std::unique_ptr<MetalTexture>> baseColorTextures;
    std::vector<uint32_t> materialBaseColorTextureIndices;
    std::vector<MetalMeshDrawRange> drawRanges;
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
    std::vector<std::unique_ptr<MetalTexture>> baseColorTextures;
    std::vector<uint32_t> materialBaseColorTextureIndices;
    baseColorTextures.reserve(meshData.images.size() + 1);
    materialBaseColorTextureIndices.reserve(materials.size());

    const std::string vertexLabel = baseLabel + " Vertices";
    const std::string drawRangeLabel = baseLabel + " Draw Ranges";
    const std::string materialLabel = baseLabel + " Materials";

    auto defaultTexture = std::make_unique<MetalTexture>(*m_impl->deviceContext);
    if (!createDefaultBaseColorTexture(*defaultTexture)) {
        return false;
    }
    baseColorTextures.push_back(std::move(defaultTexture));

    for (std::size_t imageIndex = 0; imageIndex < meshData.images.size(); ++imageIndex) {
        const core::MeshImageData& image = meshData.images[imageIndex];
        const std::string textureLabel = baseLabel + " Base Color " + std::to_string(imageIndex);
        std::unique_ptr<MetalTexture> texture;
        if (!createBaseColorTexture(*m_impl->deviceContext, image, textureLabel, texture)) {
            return false;
        }
        baseColorTextures.push_back(std::move(texture));
    }

    for (const core::MeshMaterial& material : meshData.materials) {
        uint32_t textureIndex = 0;
        if (material.baseColorTextureIndex >= 0 &&
            static_cast<std::size_t>(material.baseColorTextureIndex) < meshData.images.size()) {
            textureIndex = static_cast<uint32_t>(material.baseColorTextureIndex + 1);
        }
        materialBaseColorTextureIndices.push_back(textureIndex);
    }
    if (materialBaseColorTextureIndices.empty()) {
        materialBaseColorTextureIndices.push_back(0);
    }

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
    m_impl->baseColorTextures = std::move(baseColorTextures);
    m_impl->materialBaseColorTextureIndices = std::move(materialBaseColorTextureIndices);
    m_impl->drawRanges = std::move(drawRanges);
    m_impl->vertexCount = meshData.vertices.size();
    m_impl->drawRangeCount = static_cast<uint32_t>(m_impl->drawRanges.size());
    m_impl->materialCount = static_cast<uint32_t>(materials.size());
    return true;
}

void MetalMesh::reset()
{
    m_impl->vertexBuffer.reset();
    m_impl->drawRangeBuffer.reset();
    m_impl->materialBuffer.reset();
    m_impl->baseColorTextures.clear();
    m_impl->materialBaseColorTextureIndices.clear();
    m_impl->drawRanges.clear();
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

const MetalMeshDrawRange* MetalMesh::drawRange(uint32_t index) const
{
    return index < m_impl->drawRanges.size() ? &m_impl->drawRanges[index] : nullptr;
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

void* MetalMesh::baseColorTexture(uint32_t materialIndex) const
{
    if (materialIndex >= m_impl->materialBaseColorTextureIndices.size()) {
        return nullptr;
    }

    const uint32_t textureIndex = m_impl->materialBaseColorTextureIndices[materialIndex];
    if (textureIndex >= m_impl->baseColorTextures.size()) {
        return nullptr;
    }

    const std::unique_ptr<MetalTexture>& texture = m_impl->baseColorTextures[textureIndex];
    return texture == nullptr ? nullptr : texture->nativeTexture();
}

} // namespace mesh2splat::metal
