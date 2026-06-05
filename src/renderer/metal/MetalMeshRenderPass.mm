#include "MetalMeshRenderPass.hpp"

#include "MetalMesh.hpp"
#include "MetalPipelineCache.hpp"
#include "MetalRenderStateCache.hpp"
#include "MetalSceneResources.hpp"
#include "MetalShaderLibrary.hpp"

#import <Metal/Metal.h>

namespace mesh2splat::metal {

struct MetalMeshRenderPass::Impl {
    void* renderPipelineState = nullptr;
    void* depthStencilState = nullptr;
    void* samplerState = nullptr;
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
    MetalTextureFormat depthFormat)
{
    MetalRenderPipelineDesc pipelineDesc;
    pipelineDesc.label = "Mesh Preview Pipeline";
    pipelineDesc.vertexFunction = "meshVertex";
    pipelineDesc.fragmentFunction = "meshFragment";
    pipelineDesc.colorFormat = colorFormat;
    pipelineDesc.depthFormat = depthFormat;
    pipelineDesc.depthEnabled = true;
    pipelineDesc.blendingEnabled = false;

    m_impl->renderPipelineState = pipelineCache.renderPipeline(shaderLibrary, pipelineDesc);
    if (m_impl->renderPipelineState == nullptr) {
        return false;
    }

    MetalDepthStencilDesc depthDesc;
    depthDesc.label = "Mesh Preview Depth";
    depthDesc.depthTestEnabled = true;
    depthDesc.depthWriteEnabled = true;
    depthDesc.depthCompareFunction = MetalCompareFunction::LessEqual;
    m_impl->depthStencilState = renderStateCache.depthStencilState(depthDesc);
    if (m_impl->depthStencilState == nullptr) {
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
    m_impl->samplerState = renderStateCache.samplerState(samplerDesc);
    return m_impl->samplerState != nullptr;
}

bool MetalMeshRenderPass::isReady() const
{
    return m_impl->renderPipelineState != nullptr && m_impl->depthStencilState != nullptr &&
        m_impl->samplerState != nullptr;
}

void MetalMeshRenderPass::encode(
    void* renderCommandEncoder,
    const MetalSceneResources& sceneResources,
    void* frameUniformBuffer) const
{
    if (!isReady() || renderCommandEncoder == nullptr || frameUniformBuffer == nullptr || !sceneResources.isValid()) {
        return;
    }

    id<MTLRenderCommandEncoder> encoder = (__bridge id<MTLRenderCommandEncoder>)renderCommandEncoder;
    id<MTLRenderPipelineState> pipelineState = (__bridge id<MTLRenderPipelineState>)m_impl->renderPipelineState;
    id<MTLDepthStencilState> depthStencilState = (__bridge id<MTLDepthStencilState>)m_impl->depthStencilState;
    id<MTLSamplerState> samplerState = (__bridge id<MTLSamplerState>)m_impl->samplerState;
    id<MTLBuffer> frameBuffer = (__bridge id<MTLBuffer>)frameUniformBuffer;

    [encoder setRenderPipelineState:pipelineState];
    [encoder setDepthStencilState:depthStencilState];
    [encoder setVertexBuffer:frameBuffer offset:0 atIndex:1];
    [encoder setFragmentSamplerState:samplerState atIndex:0];

    for (std::size_t meshIndex = 0; meshIndex < sceneResources.meshCount(); ++meshIndex) {
        const MetalMesh* mesh = sceneResources.meshAt(meshIndex);
        if (mesh == nullptr || !mesh->isValid() || mesh->vertexCount() == 0) {
            continue;
        }

        id<MTLBuffer> vertexBuffer = (__bridge id<MTLBuffer>)mesh->vertexBuffer();
        id<MTLBuffer> materialBuffer = (__bridge id<MTLBuffer>)mesh->materialBuffer();
        [encoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
        [encoder setFragmentBuffer:materialBuffer offset:0 atIndex:0];

        for (uint32_t rangeIndex = 0; rangeIndex < mesh->drawRangeCount(); ++rangeIndex) {
            const MetalMeshDrawRange* range = mesh->drawRange(rangeIndex);
            if (range == nullptr || range->vertexCount == 0 || range->materialIndex >= mesh->materialCount()) {
                continue;
            }

            uint32_t materialIndex = range->materialIndex;
            id<MTLTexture> baseColorTexture = (__bridge id<MTLTexture>)mesh->baseColorTexture(materialIndex);
            id<MTLTexture> metallicRoughnessTexture =
                (__bridge id<MTLTexture>)mesh->metallicRoughnessTexture(materialIndex);
            id<MTLTexture> normalTexture = (__bridge id<MTLTexture>)mesh->normalTexture(materialIndex);
            id<MTLTexture> occlusionTexture = (__bridge id<MTLTexture>)mesh->occlusionTexture(materialIndex);
            id<MTLTexture> emissiveTexture = (__bridge id<MTLTexture>)mesh->emissiveTexture(materialIndex);
            if (baseColorTexture == nil || metallicRoughnessTexture == nil || normalTexture == nil ||
                occlusionTexture == nil || emissiveTexture == nil) {
                continue;
            }

            [encoder setFragmentTexture:baseColorTexture atIndex:0];
            [encoder setFragmentTexture:metallicRoughnessTexture atIndex:1];
            [encoder setFragmentTexture:normalTexture atIndex:2];
            [encoder setFragmentTexture:occlusionTexture atIndex:3];
            [encoder setFragmentTexture:emissiveTexture atIndex:4];
            [encoder setFragmentBytes:&materialIndex length:sizeof(materialIndex) atIndex:1];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                         vertexStart:range->vertexOffset
                         vertexCount:range->vertexCount];
        }
    }
}

} // namespace mesh2splat::metal
