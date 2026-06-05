#include "MetalGaussianSortPass.hpp"

#include "MetalGaussianBuffer.hpp"
#include "MetalGaussianSortBuffer.hpp"
#include "MetalPipelineCache.hpp"
#include "MetalShaderLibrary.hpp"

#import <Metal/Metal.h>

#include <algorithm>
#include <cstdint>

namespace mesh2splat::metal {
namespace {

struct GaussianSortParams {
    uint32_t gaussianCount = 0;
    uint32_t flags = 0;
    uint32_t reserved0 = 0;
    uint32_t reserved1 = 0;
};

static_assert(sizeof(GaussianSortParams) == 16, "GaussianSortParams must match the Metal shader layout.");

} // namespace

struct MetalGaussianSortPass::Impl {
    void* depthKeyPipelineState = nullptr;
};

MetalGaussianSortPass::MetalGaussianSortPass()
    : m_impl(std::make_unique<Impl>())
{
}

MetalGaussianSortPass::~MetalGaussianSortPass() = default;

MetalGaussianSortPass::MetalGaussianSortPass(MetalGaussianSortPass&&) noexcept = default;

MetalGaussianSortPass& MetalGaussianSortPass::operator=(MetalGaussianSortPass&&) noexcept = default;

bool MetalGaussianSortPass::initialize(MetalShaderLibrary& shaderLibrary, MetalPipelineCache& pipelineCache)
{
    MetalComputePipelineDesc desc;
    desc.label = "Gaussian Depth Key Pipeline";
    desc.function = "gaussianDepthKeyKernel";
    m_impl->depthKeyPipelineState = pipelineCache.computePipeline(shaderLibrary, desc);
    return m_impl->depthKeyPipelineState != nullptr;
}

bool MetalGaussianSortPass::isReady() const
{
    return m_impl->depthKeyPipelineState != nullptr;
}

bool MetalGaussianSortPass::encodeDepthKeys(
    void* commandBuffer,
    const MetalGaussianBuffer& gaussianBuffer,
    MetalGaussianSortBuffer& sortBuffer,
    void* frameUniformBuffer) const
{
    if (!isReady() || commandBuffer == nullptr || frameUniformBuffer == nullptr ||
        !gaussianBuffer.isValid() || !sortBuffer.isValid() ||
        gaussianBuffer.count() == 0 || gaussianBuffer.count() > sortBuffer.capacity()) {
        return false;
    }

    id<MTLCommandBuffer> nativeCommandBuffer = (__bridge id<MTLCommandBuffer>)commandBuffer;
    id<MTLComputePipelineState> pipelineState =
        (__bridge id<MTLComputePipelineState>)m_impl->depthKeyPipelineState;
    id<MTLBuffer> gaussianBufferHandle = (__bridge id<MTLBuffer>)gaussianBuffer.nativeBuffer();
    id<MTLBuffer> frameBuffer = (__bridge id<MTLBuffer>)frameUniformBuffer;
    id<MTLBuffer> keyBuffer = (__bridge id<MTLBuffer>)sortBuffer.nativeKeyBuffer();
    id<MTLBuffer> indexBuffer = (__bridge id<MTLBuffer>)sortBuffer.nativeIndexBuffer();
    if (nativeCommandBuffer == nil || pipelineState == nil || gaussianBufferHandle == nil ||
        frameBuffer == nil || keyBuffer == nil || indexBuffer == nil) {
        return false;
    }

    if (!sortBuffer.setCount(gaussianBuffer.count())) {
        return false;
    }

    id<MTLComputeCommandEncoder> encoder = [nativeCommandBuffer computeCommandEncoder];
    if (encoder == nil) {
        return false;
    }

    encoder.label = @"Mesh2Splat Gaussian Depth Keys";
    [encoder setComputePipelineState:pipelineState];
    [encoder setBuffer:gaussianBufferHandle offset:0 atIndex:0];
    [encoder setBuffer:frameBuffer offset:0 atIndex:1];
    [encoder setBuffer:keyBuffer offset:0 atIndex:2];
    [encoder setBuffer:indexBuffer offset:0 atIndex:3];

    GaussianSortParams params;
    params.gaussianCount = gaussianBuffer.count();
    [encoder setBytes:&params length:sizeof(params) atIndex:4];

    const NSUInteger threadExecutionWidth = std::max<NSUInteger>(1, pipelineState.threadExecutionWidth);
    const NSUInteger maxThreads = std::max<NSUInteger>(1, pipelineState.maxTotalThreadsPerThreadgroup);
    const NSUInteger threadsPerGroup = std::min<NSUInteger>(threadExecutionWidth, maxThreads);
    [encoder dispatchThreads:MTLSizeMake(gaussianBuffer.count(), 1, 1)
       threadsPerThreadgroup:MTLSizeMake(threadsPerGroup, 1, 1)];
    [encoder endEncoding];
    return true;
}

} // namespace mesh2splat::metal
