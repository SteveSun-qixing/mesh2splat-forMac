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
    uint32_t sortCapacity = 0;
    uint32_t reserved0 = 0;
    uint32_t reserved1 = 0;
};

struct BitonicSortParams {
    uint32_t sortCapacity = 0;
    uint32_t stageSize = 0;
    uint32_t passSize = 0;
    uint32_t reserved = 0;
};

static_assert(sizeof(GaussianSortParams) == 16, "GaussianSortParams must match the Metal shader layout.");
static_assert(sizeof(BitonicSortParams) == 16, "BitonicSortParams must match the Metal shader layout.");

bool isPowerOfTwo(std::size_t value)
{
    return value != 0 && (value & (value - 1)) == 0;
}

} // namespace

struct MetalGaussianSortPass::Impl {
    void* depthKeyPipelineState = nullptr;
    void* bitonicPipelineState = nullptr;
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
    if (m_impl->depthKeyPipelineState == nullptr) {
        return false;
    }

    MetalComputePipelineDesc bitonicDesc;
    bitonicDesc.label = "Gaussian Bitonic Sort Pipeline";
    bitonicDesc.function = "gaussianBitonicSortKernel";
    m_impl->bitonicPipelineState = pipelineCache.computePipeline(shaderLibrary, bitonicDesc);
    return m_impl->bitonicPipelineState != nullptr;
}

bool MetalGaussianSortPass::isReady() const
{
    return m_impl->depthKeyPipelineState != nullptr && m_impl->bitonicPipelineState != nullptr;
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
    id<MTLComputePipelineState> bitonicPipelineState =
        (__bridge id<MTLComputePipelineState>)m_impl->bitonicPipelineState;
    id<MTLBuffer> gaussianBufferHandle = (__bridge id<MTLBuffer>)gaussianBuffer.nativeBuffer();
    id<MTLBuffer> frameBuffer = (__bridge id<MTLBuffer>)frameUniformBuffer;
    id<MTLBuffer> keyBuffer = (__bridge id<MTLBuffer>)sortBuffer.nativeKeyBuffer();
    id<MTLBuffer> indexBuffer = (__bridge id<MTLBuffer>)sortBuffer.nativeIndexBuffer();
    if (nativeCommandBuffer == nil || pipelineState == nil || bitonicPipelineState == nil || gaussianBufferHandle == nil ||
        frameBuffer == nil || keyBuffer == nil || indexBuffer == nil) {
        return false;
    }

    if (!isPowerOfTwo(sortBuffer.capacity()) ||
        sortBuffer.capacity() > static_cast<std::size_t>(UINT32_MAX) ||
        !sortBuffer.setCount(gaussianBuffer.count())) {
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
    params.sortCapacity = static_cast<uint32_t>(sortBuffer.capacity());
    [encoder setBytes:&params length:sizeof(params) atIndex:4];

    const NSUInteger threadExecutionWidth = std::max<NSUInteger>(1, pipelineState.threadExecutionWidth);
    const NSUInteger maxThreads = std::max<NSUInteger>(1, pipelineState.maxTotalThreadsPerThreadgroup);
    const NSUInteger threadsPerGroup = std::min<NSUInteger>(threadExecutionWidth, maxThreads);
    [encoder dispatchThreads:MTLSizeMake(sortBuffer.capacity(), 1, 1)
       threadsPerThreadgroup:MTLSizeMake(threadsPerGroup, 1, 1)];
    [encoder endEncoding];

    id<MTLComputeCommandEncoder> sortEncoder = [nativeCommandBuffer computeCommandEncoder];
    if (sortEncoder == nil) {
        return false;
    }

    sortEncoder.label = @"Mesh2Splat Gaussian Bitonic Sort";
    [sortEncoder setComputePipelineState:bitonicPipelineState];
    [sortEncoder setBuffer:keyBuffer offset:0 atIndex:0];
    [sortEncoder setBuffer:indexBuffer offset:0 atIndex:1];

    const NSUInteger sortThreadExecutionWidth = std::max<NSUInteger>(1, bitonicPipelineState.threadExecutionWidth);
    const NSUInteger sortMaxThreads = std::max<NSUInteger>(1, bitonicPipelineState.maxTotalThreadsPerThreadgroup);
    const NSUInteger sortThreadsPerGroup = std::min<NSUInteger>(sortThreadExecutionWidth, sortMaxThreads);

    const uint32_t sortCapacity = static_cast<uint32_t>(sortBuffer.capacity());
    for (uint32_t stageSize = 2; stageSize <= sortCapacity;) {
        for (uint32_t passSize = stageSize >> 1; passSize > 0; passSize >>= 1) {
            BitonicSortParams sortParams;
            sortParams.sortCapacity = sortCapacity;
            sortParams.stageSize = stageSize;
            sortParams.passSize = passSize;
            [sortEncoder setBytes:&sortParams length:sizeof(sortParams) atIndex:2];
            [sortEncoder dispatchThreads:MTLSizeMake(sortCapacity, 1, 1)
                    threadsPerThreadgroup:MTLSizeMake(sortThreadsPerGroup, 1, 1)];
        }

        if (stageSize == sortCapacity) {
            break;
        }
        stageSize <<= 1;
    }

    [sortEncoder endEncoding];
    return true;
}

} // namespace mesh2splat::metal
