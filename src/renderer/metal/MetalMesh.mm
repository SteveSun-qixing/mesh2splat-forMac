#include "MetalMesh.hpp"

#include "MetalBuffer.hpp"
#include "MetalDeviceContext.hpp"
#include "MetalResourceUploader.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <string>
#include <unordered_map>
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

uint32_t normalizedSamplesPerTriangle(uint32_t samplesPerTriangle)
{
    if (samplesPerTriangle <= 1) {
        return 1;
    }
    if (samplesPerTriangle <= 4) {
        return 4;
    }
    return 9;
}

float triangleArea(
    const core::MeshVertex& vertex0,
    const core::MeshVertex& vertex1,
    const core::MeshVertex& vertex2)
{
    const float edge0[3] = {
        vertex1.position[0] - vertex0.position[0],
        vertex1.position[1] - vertex0.position[1],
        vertex1.position[2] - vertex0.position[2],
    };
    const float edge1[3] = {
        vertex2.position[0] - vertex0.position[0],
        vertex2.position[1] - vertex0.position[1],
        vertex2.position[2] - vertex0.position[2],
    };
    const float crossProduct[3] = {
        edge0[1] * edge1[2] - edge0[2] * edge1[1],
        edge0[2] * edge1[0] - edge0[0] * edge1[2],
        edge0[0] * edge1[1] - edge0[1] * edge1[0],
    };
    const float lengthSquared =
        crossProduct[0] * crossProduct[0] +
        crossProduct[1] * crossProduct[1] +
        crossProduct[2] * crossProduct[2];
    return 0.5f * std::sqrt(lengthSquared);
}

float areaSampleDensity(const MetalMeshDrawRange& range, uint32_t triangleCount, uint32_t maxSamplesPerTriangle)
{
    if (range.surfaceArea <= 0.0f || triangleCount == 0 || maxSamplesPerTriangle <= 1) {
        return 0.0f;
    }

    const double targetSampleCount = static_cast<double>(triangleCount) * static_cast<double>(maxSamplesPerTriangle);
    const double density = targetSampleCount / static_cast<double>(range.surfaceArea);
    if (!std::isfinite(density) || density <= 0.0) {
        return 0.0f;
    }

    return static_cast<float>(std::min<double>(density, std::numeric_limits<float>::max()));
}

uint32_t activeSamplesForTriangle(float area, float density, uint32_t maxSamplesPerTriangle)
{
    if (maxSamplesPerTriangle <= 1 || density <= 0.0f || area <= 1.0e-12f) {
        return maxSamplesPerTriangle;
    }

    constexpr double kCapacityCeilBias = 1.0e-5;
    const double scaledArea = static_cast<double>(area) * static_cast<double>(density);
    const double biasedSamples = std::ceil(scaledArea + kCapacityCeilBias);
    if (!std::isfinite(biasedSamples) || biasedSamples >= maxSamplesPerTriangle) {
        return maxSamplesPerTriangle;
    }

    const uint32_t areaSamples = std::max<uint32_t>(
        static_cast<uint32_t>(biasedSamples),
        1);
    return std::min(areaSamples, maxSamplesPerTriangle);
}

std::size_t conversionCapacityForRange(
    const std::vector<core::MeshVertex>& vertices,
    const MetalMeshDrawRange& range,
    uint32_t maxSamplesPerTriangle)
{
    const uint32_t sampleCount = normalizedSamplesPerTriangle(maxSamplesPerTriangle);
    if (range.vertexCount == 0 || range.vertexCount % 3 != 0 ||
        range.vertexOffset > vertices.size() ||
        range.vertexCount > vertices.size() - range.vertexOffset) {
        return 0;
    }

    const uint32_t triangleCount = range.vertexCount / 3;
    const float density = areaSampleDensity(range, triangleCount, sampleCount);
    std::size_t capacity = 0;
    for (uint32_t vertexIndex = range.vertexOffset;
         vertexIndex < range.vertexOffset + range.vertexCount;
         vertexIndex += 3) {
        const float area = triangleArea(
            vertices[vertexIndex],
            vertices[vertexIndex + 1],
            vertices[vertexIndex + 2]);
        capacity += activeSamplesForTriangle(area, density, sampleCount);
    }
    return capacity;
}

std::size_t conversionCapacityForRanges(
    const std::vector<core::MeshVertex>& vertices,
    const std::vector<MetalMeshDrawRange>& ranges,
    uint32_t maxSamplesPerTriangle)
{
    std::size_t capacity = 0;
    for (const MetalMeshDrawRange& range : ranges) {
        const std::size_t rangeCapacity = conversionCapacityForRange(vertices, range, maxSamplesPerTriangle);
        if (rangeCapacity > std::numeric_limits<std::size_t>::max() - capacity) {
            return std::numeric_limits<std::size_t>::max();
        }
        capacity += rangeCapacity;
    }
    return capacity;
}

float fallbackRangeSurfaceArea(const core::MeshData& meshData, const core::MeshDrawRange& range)
{
    if (meshData.surfaceArea <= 0.0f || meshData.vertices.empty()) {
        return 0.0f;
    }

    return meshData.surfaceArea *
        (static_cast<float>(range.vertexCount) / static_cast<float>(meshData.vertices.size()));
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

bool createDefaultMetallicRoughnessTexture(MetalTexture& texture)
{
    const uint8_t defaultPixel[4] = {0, 255, 0, 255};
    return texture.create2D(
        1,
        1,
        MetalTextureFormat::RGBA8Unorm,
        MetalTextureUsage::ShaderRead,
        "Default Metallic Roughness Texture") &&
        texture.upload2D(defaultPixel, sizeof(defaultPixel), 1, 1);
}

bool createDefaultNormalTexture(MetalTexture& texture)
{
    const uint8_t defaultPixel[4] = {128, 128, 255, 255};
    return texture.create2D(
        1,
        1,
        MetalTextureFormat::RGBA8Unorm,
        MetalTextureUsage::ShaderRead,
        "Default Normal Texture") &&
        texture.upload2D(defaultPixel, sizeof(defaultPixel), 1, 1);
}

bool createDefaultOcclusionTexture(MetalTexture& texture)
{
    const uint8_t whitePixel[4] = {255, 255, 255, 255};
    return texture.create2D(
        1,
        1,
        MetalTextureFormat::RGBA8Unorm,
        MetalTextureUsage::ShaderRead,
        "Default Occlusion Texture") &&
        texture.upload2D(whitePixel, sizeof(whitePixel), 1, 1);
}

bool createDefaultEmissiveTexture(MetalTexture& texture)
{
    const uint8_t whitePixel[4] = {255, 255, 255, 255};
    return texture.create2D(
        1,
        1,
        MetalTextureFormat::RGBA8UnormSrgb,
        MetalTextureUsage::ShaderRead,
        "Default Emissive Texture") &&
        texture.upload2D(whitePixel, sizeof(whitePixel), 1, 1);
}

bool createMaterialTexture(
    MetalDeviceContext& deviceContext,
    const core::MeshImageData& image,
    const std::string& label,
    MetalTextureFormat format,
    std::unique_ptr<MetalTexture>& texture)
{
    if (image.width == 0 || image.height == 0 || image.rgba8.empty()) {
        return false;
    }

    texture = std::make_unique<MetalTexture>(deviceContext);
    return texture->create2D(
        image.width,
        image.height,
        format,
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
    std::vector<std::unique_ptr<MetalTexture>> metallicRoughnessTextures;
    std::vector<std::unique_ptr<MetalTexture>> normalTextures;
    std::vector<std::unique_ptr<MetalTexture>> occlusionTextures;
    std::vector<std::unique_ptr<MetalTexture>> emissiveTextures;
    std::vector<uint32_t> materialBaseColorTextureIndices;
    std::vector<uint32_t> materialMetallicRoughnessTextureIndices;
    std::vector<uint32_t> materialNormalTextureIndices;
    std::vector<uint32_t> materialOcclusionTextureIndices;
    std::vector<uint32_t> materialEmissiveTextureIndices;
    std::vector<MetalMeshDrawRange> drawRanges;
    std::size_t conversionCapacity1 = 0;
    std::size_t conversionCapacity4 = 0;
    std::size_t conversionCapacity9 = 0;
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
            meshData.surfaceArea,
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
                range.surfaceArea > 0.0f ? range.surfaceArea : fallbackRangeSurfaceArea(meshData, range),
            });
        }
    }

    if (!canFitUInt32(drawRanges.size())) {
        return false;
    }

    const std::size_t conversionCapacity1 = conversionCapacityForRanges(meshData.vertices, drawRanges, 1);
    const std::size_t conversionCapacity4 = conversionCapacityForRanges(meshData.vertices, drawRanges, 4);
    const std::size_t conversionCapacity9 = conversionCapacityForRanges(meshData.vertices, drawRanges, 9);

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
    std::vector<std::unique_ptr<MetalTexture>> metallicRoughnessTextures;
    std::vector<std::unique_ptr<MetalTexture>> normalTextures;
    std::vector<std::unique_ptr<MetalTexture>> occlusionTextures;
    std::vector<std::unique_ptr<MetalTexture>> emissiveTextures;
    std::vector<uint32_t> materialBaseColorTextureIndices;
    std::vector<uint32_t> materialMetallicRoughnessTextureIndices;
    std::vector<uint32_t> materialNormalTextureIndices;
    std::vector<uint32_t> materialOcclusionTextureIndices;
    std::vector<uint32_t> materialEmissiveTextureIndices;
    std::unordered_map<int32_t, uint32_t> baseColorTextureMap;
    std::unordered_map<int32_t, uint32_t> metallicRoughnessTextureMap;
    std::unordered_map<int32_t, uint32_t> normalTextureMap;
    std::unordered_map<int32_t, uint32_t> occlusionTextureMap;
    std::unordered_map<int32_t, uint32_t> emissiveTextureMap;
    baseColorTextures.reserve(meshData.images.size() + 1);
    metallicRoughnessTextures.reserve(meshData.images.size() + 1);
    normalTextures.reserve(meshData.images.size() + 1);
    occlusionTextures.reserve(meshData.images.size() + 1);
    emissiveTextures.reserve(meshData.images.size() + 1);
    materialBaseColorTextureIndices.reserve(materials.size());
    materialMetallicRoughnessTextureIndices.reserve(materials.size());
    materialNormalTextureIndices.reserve(materials.size());
    materialOcclusionTextureIndices.reserve(materials.size());
    materialEmissiveTextureIndices.reserve(materials.size());

    const std::string vertexLabel = baseLabel + " Vertices";
    const std::string drawRangeLabel = baseLabel + " Draw Ranges";
    const std::string materialLabel = baseLabel + " Materials";

    auto defaultTexture = std::make_unique<MetalTexture>(*m_impl->deviceContext);
    if (!createDefaultBaseColorTexture(*defaultTexture)) {
        return false;
    }
    baseColorTextures.push_back(std::move(defaultTexture));

    auto defaultMetallicRoughnessTexture = std::make_unique<MetalTexture>(*m_impl->deviceContext);
    if (!createDefaultMetallicRoughnessTexture(*defaultMetallicRoughnessTexture)) {
        return false;
    }
    metallicRoughnessTextures.push_back(std::move(defaultMetallicRoughnessTexture));

    auto defaultNormalTexture = std::make_unique<MetalTexture>(*m_impl->deviceContext);
    if (!createDefaultNormalTexture(*defaultNormalTexture)) {
        return false;
    }
    normalTextures.push_back(std::move(defaultNormalTexture));

    auto defaultOcclusionTexture = std::make_unique<MetalTexture>(*m_impl->deviceContext);
    if (!createDefaultOcclusionTexture(*defaultOcclusionTexture)) {
        return false;
    }
    occlusionTextures.push_back(std::move(defaultOcclusionTexture));

    auto defaultEmissiveTexture = std::make_unique<MetalTexture>(*m_impl->deviceContext);
    if (!createDefaultEmissiveTexture(*defaultEmissiveTexture)) {
        return false;
    }
    emissiveTextures.push_back(std::move(defaultEmissiveTexture));

    auto resolveMaterialTexture = [this, &meshData, &baseLabel](
                                      int32_t imageIndex,
                                      MetalTextureFormat format,
                                      const char* labelSuffix,
                                      std::vector<std::unique_ptr<MetalTexture>>& textures,
                                      std::unordered_map<int32_t, uint32_t>& textureMap) -> uint32_t {
        if (imageIndex < 0 || static_cast<std::size_t>(imageIndex) >= meshData.images.size()) {
            return 0;
        }

        const auto found = textureMap.find(imageIndex);
        if (found != textureMap.end()) {
            return found->second;
        }

        const core::MeshImageData& image = meshData.images[imageIndex];
        const std::string textureLabel = baseLabel + " " + labelSuffix + " " + std::to_string(imageIndex);
        std::unique_ptr<MetalTexture> texture;
        if (!createMaterialTexture(*m_impl->deviceContext, image, textureLabel, format, texture)) {
            return 0;
        }

        textures.push_back(std::move(texture));
        const uint32_t textureIndex = static_cast<uint32_t>(textures.size() - 1);
        textureMap.insert_or_assign(imageIndex, textureIndex);
        return textureIndex;
    };

    for (const core::MeshMaterial& material : meshData.materials) {
        materialBaseColorTextureIndices.push_back(resolveMaterialTexture(
            material.baseColorTextureIndex,
            MetalTextureFormat::RGBA8UnormSrgb,
            "Base Color",
            baseColorTextures,
            baseColorTextureMap));
        materialMetallicRoughnessTextureIndices.push_back(resolveMaterialTexture(
            material.metallicRoughnessTextureIndex,
            MetalTextureFormat::RGBA8Unorm,
            "Metallic Roughness",
            metallicRoughnessTextures,
            metallicRoughnessTextureMap));
        materialNormalTextureIndices.push_back(resolveMaterialTexture(
            material.normalTextureIndex,
            MetalTextureFormat::RGBA8Unorm,
            "Normal",
            normalTextures,
            normalTextureMap));
        materialOcclusionTextureIndices.push_back(resolveMaterialTexture(
            material.occlusionTextureIndex,
            MetalTextureFormat::RGBA8Unorm,
            "Occlusion",
            occlusionTextures,
            occlusionTextureMap));
        materialEmissiveTextureIndices.push_back(resolveMaterialTexture(
            material.emissiveTextureIndex,
            MetalTextureFormat::RGBA8UnormSrgb,
            "Emissive",
            emissiveTextures,
            emissiveTextureMap));
    }
    if (materialBaseColorTextureIndices.empty()) {
        materialBaseColorTextureIndices.push_back(0);
    }
    if (materialMetallicRoughnessTextureIndices.empty()) {
        materialMetallicRoughnessTextureIndices.push_back(0);
    }
    if (materialNormalTextureIndices.empty()) {
        materialNormalTextureIndices.push_back(0);
    }
    if (materialOcclusionTextureIndices.empty()) {
        materialOcclusionTextureIndices.push_back(0);
    }
    if (materialEmissiveTextureIndices.empty()) {
        materialEmissiveTextureIndices.push_back(0);
    }

    MetalResourceUploadBatch staticBufferUpload(
        m_impl->deviceContext->nativeDevice(),
        m_impl->deviceContext->nativeCommandQueue(),
        "Mesh2Splat Mesh Static Buffer Upload",
        "Mesh2Splat Mesh Static Buffer Upload Blit");
    if (!vertexBuffer->createPrivateWithData(
            meshData.vertices.size() * sizeof(core::MeshVertex),
            meshData.vertices.data(),
            staticBufferUpload,
            vertexLabel.c_str()) ||
        !drawRangeBuffer->createPrivateWithData(
            drawRanges.size() * sizeof(MetalMeshDrawRange),
            drawRanges.data(),
            staticBufferUpload,
            drawRangeLabel.c_str()) ||
        !materialBuffer->createPrivateWithData(
            materials.size() * sizeof(MetalMeshMaterial),
            materials.data(),
            staticBufferUpload,
            materialLabel.c_str()) ||
        !staticBufferUpload.commitAndWait()) {
        return false;
    }

    m_impl->vertexBuffer = std::move(vertexBuffer);
    m_impl->drawRangeBuffer = std::move(drawRangeBuffer);
    m_impl->materialBuffer = std::move(materialBuffer);
    m_impl->baseColorTextures = std::move(baseColorTextures);
    m_impl->metallicRoughnessTextures = std::move(metallicRoughnessTextures);
    m_impl->normalTextures = std::move(normalTextures);
    m_impl->occlusionTextures = std::move(occlusionTextures);
    m_impl->emissiveTextures = std::move(emissiveTextures);
    m_impl->materialBaseColorTextureIndices = std::move(materialBaseColorTextureIndices);
    m_impl->materialMetallicRoughnessTextureIndices = std::move(materialMetallicRoughnessTextureIndices);
    m_impl->materialNormalTextureIndices = std::move(materialNormalTextureIndices);
    m_impl->materialOcclusionTextureIndices = std::move(materialOcclusionTextureIndices);
    m_impl->materialEmissiveTextureIndices = std::move(materialEmissiveTextureIndices);
    m_impl->drawRanges = std::move(drawRanges);
    m_impl->conversionCapacity1 = conversionCapacity1;
    m_impl->conversionCapacity4 = conversionCapacity4;
    m_impl->conversionCapacity9 = conversionCapacity9;
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
    m_impl->metallicRoughnessTextures.clear();
    m_impl->normalTextures.clear();
    m_impl->occlusionTextures.clear();
    m_impl->emissiveTextures.clear();
    m_impl->materialBaseColorTextureIndices.clear();
    m_impl->materialMetallicRoughnessTextureIndices.clear();
    m_impl->materialNormalTextureIndices.clear();
    m_impl->materialOcclusionTextureIndices.clear();
    m_impl->materialEmissiveTextureIndices.clear();
    m_impl->drawRanges.clear();
    m_impl->conversionCapacity1 = 0;
    m_impl->conversionCapacity4 = 0;
    m_impl->conversionCapacity9 = 0;
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

std::size_t MetalMesh::conversionCapacity(uint32_t maxSamplesPerTriangle) const
{
    const uint32_t sampleCount = normalizedSamplesPerTriangle(maxSamplesPerTriangle);
    if (sampleCount <= 1) {
        return m_impl->conversionCapacity1;
    }
    if (sampleCount <= 4) {
        return m_impl->conversionCapacity4;
    }
    return m_impl->conversionCapacity9;
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

void* MetalMesh::metallicRoughnessTexture(uint32_t materialIndex) const
{
    if (materialIndex >= m_impl->materialMetallicRoughnessTextureIndices.size()) {
        return nullptr;
    }

    const uint32_t textureIndex = m_impl->materialMetallicRoughnessTextureIndices[materialIndex];
    if (textureIndex >= m_impl->metallicRoughnessTextures.size()) {
        return nullptr;
    }

    const std::unique_ptr<MetalTexture>& texture = m_impl->metallicRoughnessTextures[textureIndex];
    return texture == nullptr ? nullptr : texture->nativeTexture();
}

void* MetalMesh::normalTexture(uint32_t materialIndex) const
{
    if (materialIndex >= m_impl->materialNormalTextureIndices.size()) {
        return nullptr;
    }

    const uint32_t textureIndex = m_impl->materialNormalTextureIndices[materialIndex];
    if (textureIndex >= m_impl->normalTextures.size()) {
        return nullptr;
    }

    const std::unique_ptr<MetalTexture>& texture = m_impl->normalTextures[textureIndex];
    return texture == nullptr ? nullptr : texture->nativeTexture();
}

void* MetalMesh::occlusionTexture(uint32_t materialIndex) const
{
    if (materialIndex >= m_impl->materialOcclusionTextureIndices.size()) {
        return nullptr;
    }

    const uint32_t textureIndex = m_impl->materialOcclusionTextureIndices[materialIndex];
    if (textureIndex >= m_impl->occlusionTextures.size()) {
        return nullptr;
    }

    const std::unique_ptr<MetalTexture>& texture = m_impl->occlusionTextures[textureIndex];
    return texture == nullptr ? nullptr : texture->nativeTexture();
}

void* MetalMesh::emissiveTexture(uint32_t materialIndex) const
{
    if (materialIndex >= m_impl->materialEmissiveTextureIndices.size()) {
        return nullptr;
    }

    const uint32_t textureIndex = m_impl->materialEmissiveTextureIndices[materialIndex];
    if (textureIndex >= m_impl->emissiveTextures.size()) {
        return nullptr;
    }

    const std::unique_ptr<MetalTexture>& texture = m_impl->emissiveTextures[textureIndex];
    return texture == nullptr ? nullptr : texture->nativeTexture();
}

} // namespace mesh2splat::metal
