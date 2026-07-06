#include "MetalMeshRenderPass.hpp"

#include "MetalBindings.hpp"
#include "MetalMesh.hpp"
#include "MetalPipelineCache.hpp"
#include "MetalRenderStateCache.hpp"
#include "MetalSceneResources.hpp"
#include "MetalShaderLibrary.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>
#include <cstdint>
#include <sstream>
#include <string>
#include <utility>

namespace mesh2splat::metal {
namespace {

constexpr const char* kMeshRenderDebugLabel = "Mesh2Splat Mesh Preview Render";
constexpr std::size_t kMaterialTextureBindingCount = 5;

NSString* stringFromUtf8(const char* value)
{
    return value == nullptr ? nil : [NSString stringWithUTF8String:value];
}

const char* textureFormatName(MetalTextureFormat format)
{
    switch (format) {
    case MetalTextureFormat::BGRA8Unorm:
        return "BGRA8Unorm";
    case MetalTextureFormat::BGRA8UnormSrgb:
        return "BGRA8UnormSrgb";
    case MetalTextureFormat::RGBA8Unorm:
        return "RGBA8Unorm";
    case MetalTextureFormat::RGBA8UnormSrgb:
        return "RGBA8UnormSrgb";
    case MetalTextureFormat::R8Unorm:
        return "R8Unorm";
    case MetalTextureFormat::Depth32Float:
        return "Depth32Float";
    }

    return "Unknown";
}

void setErrorMessage(std::string* errorMessage, std::string message)
{
    if (errorMessage != nullptr) {
        *errorMessage = std::move(message);
    }
}

void clearErrorMessage(std::string* errorMessage)
{
    if (errorMessage != nullptr) {
        errorMessage->clear();
    }
}

bool drawRangeFitsMesh(const MetalMesh& mesh, const MetalMeshDrawRange& range)
{
    return range.vertexOffset <= mesh.vertexCount() &&
        range.vertexCount <= mesh.vertexCount() - range.vertexOffset;
}

bool sceneLooksEmpty(const MetalSceneResources& sceneResources)
{
    return sceneResources.meshCount() == 0 ||
        sceneResources.totalVertexCount() == 0 ||
        sceneResources.totalDrawRangeCount() == 0;
}

std::string initializeTargetDescription(MetalTextureFormat colorFormat, MetalTextureFormat depthFormat)
{
    return "colorFormat=" + std::string(textureFormatName(colorFormat)) +
        ", depthFormat=" + textureFormatName(depthFormat);
}

std::string noDrawableRangesDiagnostic(const MetalMeshRenderPassDiagnostics& diagnostics)
{
    std::ostringstream message;
    message << "Metal mesh render pass skipped: no drawable mesh ranges were encoded"
            << " (meshes=" << diagnostics.meshCount
            << ", drawRanges=" << diagnostics.totalDrawRangeCount
            << ", skippedMeshes=" << diagnostics.skippedMeshCount
            << ", skippedDrawRanges=" << diagnostics.skippedDrawRangeCount
            << ", missingMaterialTextures=" << diagnostics.missingMaterialTextureCount
            << ").";
    return message.str();
}

} // namespace

struct MetalMeshRenderPass::Impl {
    void* renderPipelineState = nullptr;
    void* depthStencilState = nullptr;
    void* samplerState = nullptr;
    MetalTextureFormat colorFormat = MetalTextureFormat::BGRA8Unorm;
    MetalTextureFormat depthFormat = MetalTextureFormat::Depth32Float;
    bool depthEnabled = true;
    bool depthWriteEnabled = true;
    std::string debugLabel = kMeshRenderDebugLabel;
    mutable std::string lastDiagnostic;
    mutable MetalMeshRenderPassDiagnostics lastEncodeDiagnostics;

    void resetPipelineState()
    {
        renderPipelineState = nullptr;
        depthStencilState = nullptr;
        samplerState = nullptr;
    }

    void recordDiagnostic(std::string diagnostic, bool logDiagnostic = true) const
    {
        lastEncodeDiagnostics.lastMessage = diagnostic;
        if (diagnostic == lastDiagnostic) {
            return;
        }

        lastDiagnostic = std::move(diagnostic);
        if (logDiagnostic && !lastDiagnostic.empty()) {
            NSLog(@"%s", lastDiagnostic.c_str());
        }
    }

    void beginEncodeDiagnostics(const MetalSceneResources& sceneResources, bool ready) const
    {
        lastEncodeDiagnostics = {};
        lastEncodeDiagnostics.ready = ready;
        lastEncodeDiagnostics.sceneValid = sceneResources.isValid();
        lastEncodeDiagnostics.meshCount = sceneResources.meshCount();
        lastEncodeDiagnostics.totalVertexCount = sceneResources.totalVertexCount();
        lastEncodeDiagnostics.totalDrawRangeCount = sceneResources.totalDrawRangeCount();
        lastEncodeDiagnostics.totalMaterialCount = sceneResources.totalMaterialCount();
        lastEncodeDiagnostics.totalTextureCount = sceneResources.totalTextureCount();
        lastEncodeDiagnostics.emptyScene = sceneLooksEmpty(sceneResources);
        lastEncodeDiagnostics.depthEnabled = depthEnabled;
        lastEncodeDiagnostics.depthWriteEnabled = depthWriteEnabled;
        lastEncodeDiagnostics.colorFormat = textureFormatName(colorFormat);
        lastEncodeDiagnostics.depthFormat = textureFormatName(depthFormat);
        lastEncodeDiagnostics.debugLabel = debugLabel;
    }
};

MetalMeshRenderPass::MetalMeshRenderPass(MetalDeviceContext&)
    : m_impl(std::make_unique<Impl>())
{
}

MetalMeshRenderPass::~MetalMeshRenderPass() = default;

MetalMeshRenderPass::MetalMeshRenderPass(MetalMeshRenderPass&&) noexcept = default;

MetalMeshRenderPass& MetalMeshRenderPass::operator=(MetalMeshRenderPass&&) noexcept = default;

bool MetalMeshRenderPass::initialize(
    MetalShaderLibrary& shaderLibrary,
    MetalPipelineCache& pipelineCache,
    MetalRenderStateCache& renderStateCache,
    MetalTextureFormat colorFormat,
    MetalTextureFormat depthFormat,
    std::string* errorMessage)
{
    if (m_impl == nullptr) {
        setErrorMessage(errorMessage, "Failed to initialize mesh render pass: implementation storage is missing.");
        return false;
    }

    m_impl->resetPipelineState();
    m_impl->colorFormat = colorFormat;
    m_impl->depthFormat = depthFormat;
    m_impl->lastEncodeDiagnostics = {};
    m_impl->lastEncodeDiagnostics.debugLabel = m_impl->debugLabel;

    MetalRenderPipelineDesc pipelineDesc = MetalPipelineCache::meshPipelineDesc(colorFormat, depthFormat);

    std::string pipelineError;
    m_impl->renderPipelineState = pipelineCache.renderPipeline(shaderLibrary, pipelineDesc, &pipelineError);
    if (m_impl->renderPipelineState == nullptr) {
        std::string message =
            "Failed to initialize mesh render pipeline '" + pipelineDesc.vertexFunction + "/" +
            pipelineDesc.fragmentFunction + "' for " + initializeTargetDescription(colorFormat, depthFormat);
        if (!pipelineError.empty()) {
            message += ": " + pipelineError;
        } else {
            message += ": pipeline cache returned no diagnostic.";
        }
        m_impl->recordDiagnostic(message);
        setErrorMessage(errorMessage, std::move(message));
        return false;
    }

    MetalDepthStencilDesc depthDesc;
    depthDesc.label = "Mesh Preview Depth";
    depthDesc.depthTestEnabled = true;
    depthDesc.depthWriteEnabled = true;
    depthDesc.depthCompareFunction = MetalCompareFunction::LessEqual;
    m_impl->depthEnabled = depthDesc.depthTestEnabled;
    m_impl->depthWriteEnabled = depthDesc.depthWriteEnabled;
    std::string depthError;
    m_impl->depthStencilState = renderStateCache.depthStencilState(depthDesc, &depthError);
    if (m_impl->depthStencilState == nullptr) {
        std::string message = "Failed to initialize mesh render depth state.";
        if (!depthError.empty()) {
            message += " " + depthError;
        }
        m_impl->recordDiagnostic(message);
        setErrorMessage(errorMessage, std::move(message));
        return false;
    }

    MetalSamplerDesc samplerDesc;
    samplerDesc.label = "Mesh Base Color Sampler";
    samplerDesc.minFilter = MetalSamplerFilter::Linear;
    samplerDesc.magFilter = MetalSamplerFilter::Linear;
    samplerDesc.mipFilter = MetalSamplerFilter::Linear;
    samplerDesc.addressU = MetalSamplerAddressMode::Repeat;
    samplerDesc.addressV = MetalSamplerAddressMode::Repeat;
    samplerDesc.addressW = MetalSamplerAddressMode::Repeat;
    std::string samplerError;
    m_impl->samplerState = renderStateCache.samplerState(samplerDesc, &samplerError);
    if (m_impl->samplerState == nullptr) {
        std::string message = "Failed to initialize mesh render sampler state.";
        if (!samplerError.empty()) {
            message += " " + samplerError;
        }
        m_impl->recordDiagnostic(message);
        setErrorMessage(errorMessage, std::move(message));
        return false;
    }

    m_impl->recordDiagnostic(std::string{}, false);
    clearErrorMessage(errorMessage);
    return true;
}

bool MetalMeshRenderPass::isReady() const
{
    return m_impl != nullptr &&
        m_impl->renderPipelineState != nullptr && m_impl->depthStencilState != nullptr &&
        m_impl->samplerState != nullptr;
}

const std::string& MetalMeshRenderPass::lastDiagnostic() const
{
    static const std::string emptyDiagnostic;
    if (m_impl == nullptr) {
        return emptyDiagnostic;
    }

    return m_impl->lastDiagnostic;
}

MetalMeshRenderPassDiagnostics MetalMeshRenderPass::lastEncodeDiagnostics() const
{
    if (m_impl == nullptr) {
        return {};
    }

    return m_impl->lastEncodeDiagnostics;
}

void MetalMeshRenderPass::encode(
    void* renderCommandEncoder,
    const MetalSceneResources& sceneResources,
    void* frameUniformBuffer) const
{
    if (m_impl == nullptr) {
        return;
    }

    const bool ready = isReady();
    m_impl->beginEncodeDiagnostics(sceneResources, ready);
    if (!ready) {
        m_impl->recordDiagnostic("Metal mesh render pass skipped: pass is not ready.");
        return;
    }
    if (renderCommandEncoder == nullptr) {
        m_impl->recordDiagnostic("Metal mesh render pass skipped: render encoder is null.");
        return;
    }
    if (frameUniformBuffer == nullptr) {
        m_impl->recordDiagnostic("Metal mesh render pass skipped: frame uniform buffer is null.");
        return;
    }
    if (sceneLooksEmpty(sceneResources)) {
        m_impl->recordDiagnostic(std::string{}, false);
        return;
    }
    if (!sceneResources.isValid()) {
        m_impl->recordDiagnostic("Metal mesh render pass skipped: scene resources are invalid.");
        return;
    }

    id<MTLRenderCommandEncoder> encoder = (__bridge id<MTLRenderCommandEncoder>)renderCommandEncoder;
    id<MTLRenderPipelineState> pipelineState = (__bridge id<MTLRenderPipelineState>)m_impl->renderPipelineState;
    id<MTLDepthStencilState> depthStencilState = (__bridge id<MTLDepthStencilState>)m_impl->depthStencilState;
    id<MTLSamplerState> samplerState = (__bridge id<MTLSamplerState>)m_impl->samplerState;
    id<MTLBuffer> frameBuffer = (__bridge id<MTLBuffer>)frameUniformBuffer;
    if (encoder == nil || pipelineState == nil || depthStencilState == nil || samplerState == nil ||
        frameBuffer == nil) {
        m_impl->recordDiagnostic("Metal mesh render pass skipped: native Metal resources are unavailable.");
        return;
    }

    if (encoder.label == nil) {
        encoder.label = @"Mesh2Splat Drawable Render";
    }
    [encoder pushDebugGroup:stringFromUtf8(m_impl->debugLabel.c_str())];
    [encoder setRenderPipelineState:pipelineState];
    [encoder setDepthStencilState:depthStencilState];
    [encoder setVertexBuffer:frameBuffer offset:0 atIndex:bindings::mesh::vertex_buffers::kFrameUniforms];
    [encoder setFragmentBuffer:frameBuffer offset:0 atIndex:bindings::mesh::fragment_buffers::kFrameUniforms];
    [encoder setFragmentSamplerState:samplerState atIndex:bindings::mesh::fragment_samplers::kMaterialTextures];

    for (std::size_t meshIndex = 0; meshIndex < sceneResources.meshCount(); ++meshIndex) {
        const MetalMesh* mesh = sceneResources.meshAt(meshIndex);
        if (mesh == nullptr || !mesh->isValid() || mesh->vertexCount() == 0 || mesh->drawRangeCount() == 0) {
            ++m_impl->lastEncodeDiagnostics.skippedMeshCount;
            continue;
        }

        id<MTLBuffer> vertexBuffer = (__bridge id<MTLBuffer>)mesh->vertexBuffer();
        id<MTLBuffer> materialBuffer = (__bridge id<MTLBuffer>)mesh->materialBuffer();
        if (vertexBuffer == nil || materialBuffer == nil || mesh->materialCount() == 0) {
            ++m_impl->lastEncodeDiagnostics.skippedMeshCount;
            m_impl->lastEncodeDiagnostics.skippedDrawRangeCount += mesh->drawRangeCount();
            continue;
        }

        bool encodedMesh = false;
        [encoder setVertexBuffer:vertexBuffer offset:0 atIndex:bindings::mesh::vertex_buffers::kVertices];
        [encoder setFragmentBuffer:materialBuffer offset:0 atIndex:bindings::mesh::fragment_buffers::kMaterials];

        for (uint32_t rangeIndex = 0; rangeIndex < mesh->drawRangeCount(); ++rangeIndex) {
            const MetalMeshDrawRange* range = mesh->drawRange(rangeIndex);
            if (range == nullptr ||
                range->vertexCount == 0 ||
                range->vertexCount % 3 != 0 ||
                !drawRangeFitsMesh(*mesh, *range) ||
                range->materialIndex >= mesh->materialCount()) {
                ++m_impl->lastEncodeDiagnostics.skippedDrawRangeCount;
                continue;
            }

            const uint32_t materialIndex = range->materialIndex;
            id<MTLTexture> baseColorTexture = (__bridge id<MTLTexture>)mesh->baseColorTexture(materialIndex);
            id<MTLTexture> metallicRoughnessTexture =
                (__bridge id<MTLTexture>)mesh->metallicRoughnessTexture(materialIndex);
            id<MTLTexture> normalTexture = (__bridge id<MTLTexture>)mesh->normalTexture(materialIndex);
            id<MTLTexture> occlusionTexture = (__bridge id<MTLTexture>)mesh->occlusionTexture(materialIndex);
            id<MTLTexture> emissiveTexture = (__bridge id<MTLTexture>)mesh->emissiveTexture(materialIndex);
            std::size_t missingTextureCount = 0;
            missingTextureCount += baseColorTexture == nil ? 1 : 0;
            missingTextureCount += metallicRoughnessTexture == nil ? 1 : 0;
            missingTextureCount += normalTexture == nil ? 1 : 0;
            missingTextureCount += occlusionTexture == nil ? 1 : 0;
            missingTextureCount += emissiveTexture == nil ? 1 : 0;
            if (missingTextureCount > 0) {
                ++m_impl->lastEncodeDiagnostics.skippedDrawRangeCount;
                m_impl->lastEncodeDiagnostics.missingMaterialTextureCount += missingTextureCount;
                continue;
            }

            [encoder setFragmentTexture:baseColorTexture atIndex:bindings::material_textures::kBaseColor];
            [encoder setFragmentTexture:metallicRoughnessTexture
                                atIndex:bindings::material_textures::kMetallicRoughness];
            [encoder setFragmentTexture:normalTexture atIndex:bindings::material_textures::kNormal];
            [encoder setFragmentTexture:occlusionTexture atIndex:bindings::material_textures::kOcclusion];
            [encoder setFragmentTexture:emissiveTexture atIndex:bindings::material_textures::kEmissive];
            [encoder setFragmentBytes:&materialIndex
                                length:sizeof(materialIndex)
                               atIndex:bindings::mesh::fragment_buffers::kMaterialIndex];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                         vertexStart:range->vertexOffset
                         vertexCount:range->vertexCount];
            encodedMesh = true;
            ++m_impl->lastEncodeDiagnostics.encodedDrawRangeCount;
            m_impl->lastEncodeDiagnostics.drawnVertexCount += range->vertexCount;
            m_impl->lastEncodeDiagnostics.boundMaterialTextureCount += kMaterialTextureBindingCount;
        }

        if (encodedMesh) {
            ++m_impl->lastEncodeDiagnostics.encodedMeshCount;
        } else {
            ++m_impl->lastEncodeDiagnostics.skippedMeshCount;
        }
    }

    [encoder popDebugGroup];
    if (m_impl->lastEncodeDiagnostics.encodedDrawRangeCount == 0) {
        m_impl->recordDiagnostic(noDrawableRangesDiagnostic(m_impl->lastEncodeDiagnostics));
        return;
    }

    m_impl->recordDiagnostic(std::string{}, false);
}

} // namespace mesh2splat::metal
