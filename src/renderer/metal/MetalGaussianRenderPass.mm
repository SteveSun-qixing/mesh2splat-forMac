#include "MetalGaussianRenderPass.hpp"

#include "MetalGaussianBuffer.hpp"
#include "MetalGaussianSortBuffer.hpp"
#include "MetalPipelineCache.hpp"
#include "MetalRenderStateCache.hpp"
#include "MetalShaderLibrary.hpp"

#import <Metal/Metal.h>

namespace mesh2splat::metal {

struct MetalGaussianRenderPass::Impl {
    void* renderPipelineState = nullptr;
    void* depthStencilState = nullptr;
};

MetalGaussianRenderPass::MetalGaussianRenderPass(MetalDeviceContext&)
    : m_impl(std::make_unique<Impl>())
{
}

MetalGaussianRenderPass::~MetalGaussianRenderPass() = default;

MetalGaussianRenderPass::MetalGaussianRenderPass(MetalGaussianRenderPass&&) noexcept = default;

MetalGaussianRenderPass& MetalGaussianRenderPass::operator=(MetalGaussianRenderPass&&) noexcept = default;

bool MetalGaussianRenderPass::initialize(
    MetalShaderLibrary& shaderLibrary,
    MetalPipelineCache& pipelineCache,
    MetalRenderStateCache& renderStateCache,
    MetalTextureFormat colorFormat,
    MetalTextureFormat depthFormat)
{
    MetalRenderPipelineDesc pipelineDesc;
    pipelineDesc.label = "Gaussian Preview Pipeline";
    pipelineDesc.vertexFunction = "gaussianPreviewVertex";
    pipelineDesc.fragmentFunction = "gaussianPreviewFragment";
    pipelineDesc.colorFormat = colorFormat;
    pipelineDesc.depthFormat = depthFormat;
    pipelineDesc.depthEnabled = true;
    pipelineDesc.blendMode = MetalBlendMode::PremultipliedAlpha;

    m_impl->renderPipelineState = pipelineCache.renderPipeline(shaderLibrary, pipelineDesc);
    if (m_impl->renderPipelineState == nullptr) {
        return false;
    }

    MetalDepthStencilDesc depthDesc;
    depthDesc.label = "Gaussian Preview Depth";
    depthDesc.depthTestEnabled = true;
    depthDesc.depthWriteEnabled = false;
    depthDesc.depthCompareFunction = MetalCompareFunction::LessEqual;
    m_impl->depthStencilState = renderStateCache.depthStencilState(depthDesc);
    return m_impl->depthStencilState != nullptr;
}

bool MetalGaussianRenderPass::isReady() const
{
    return m_impl->renderPipelineState != nullptr && m_impl->depthStencilState != nullptr;
}

void MetalGaussianRenderPass::encode(
    void* renderCommandEncoder,
    const MetalGaussianBuffer& gaussianBuffer,
    const MetalGaussianSortBuffer& sortBuffer,
    void* frameUniformBuffer) const
{
    if (!isReady() || renderCommandEncoder == nullptr || frameUniformBuffer == nullptr ||
        !gaussianBuffer.isValid() || !sortBuffer.isValid() ||
        gaussianBuffer.count() == 0 || sortBuffer.count() == 0) {
        return;
    }

    id<MTLRenderCommandEncoder> encoder = (__bridge id<MTLRenderCommandEncoder>)renderCommandEncoder;
    id<MTLRenderPipelineState> pipelineState = (__bridge id<MTLRenderPipelineState>)m_impl->renderPipelineState;
    id<MTLDepthStencilState> depthStencilState = (__bridge id<MTLDepthStencilState>)m_impl->depthStencilState;
    id<MTLBuffer> gaussianBufferHandle = (__bridge id<MTLBuffer>)gaussianBuffer.nativeBuffer();
    id<MTLBuffer> indexBuffer = (__bridge id<MTLBuffer>)sortBuffer.nativeIndexBuffer();
    id<MTLBuffer> frameBuffer = (__bridge id<MTLBuffer>)frameUniformBuffer;
    if (encoder == nil || pipelineState == nil || depthStencilState == nil ||
        gaussianBufferHandle == nil || indexBuffer == nil || frameBuffer == nil) {
        return;
    }

    [encoder setRenderPipelineState:pipelineState];
    [encoder setDepthStencilState:depthStencilState];
    [encoder setVertexBuffer:gaussianBufferHandle offset:0 atIndex:0];
    [encoder setVertexBuffer:frameBuffer offset:0 atIndex:1];
    [encoder setVertexBuffer:indexBuffer offset:0 atIndex:2];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:6
              instanceCount:sortBuffer.count()];
}

} // namespace mesh2splat::metal
