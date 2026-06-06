#include "MetalGaussianSortPass.hpp"

#include "MetalGaussianBuffer.hpp"
#include "MetalGaussianSortBuffer.hpp"
#include "MetalDispatchUtils.hpp"
#include "MetalPipelineCache.hpp"
#include "MetalShaderLibrary.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <cstdint>

namespace mesh2splat::metal {
namespace {

struct GaussianSortParams {
    uint32_t gaussianCount = 0;
    uint32_t reserved0 = 0;
    uint32_t reserved1 = 0;
    uint32_t reserved2 = 0;
};

struct RadixSortParams {
    uint32_t itemCount = 0;
    uint32_t blockCount = 0;
    uint32_t radixShift = 0;
    uint32_t reserved = 0;
};

static_assert(sizeof(GaussianSortParams) == 16, "GaussianSortParams must match the Metal shader layout.");
static_assert(sizeof(RadixSortParams) == 16, "RadixSortParams must match the Metal shader layout.");

constexpr uint32_t kRadixBinCount = 16;
constexpr uint32_t kRadixPassCount = 8;
constexpr uint32_t kRadixSortThreadCount = 256;

} // namespace

struct MetalGaussianSortPass::Impl {
    void* depthKeyPipelineState = nullptr;
    void* radixCountPipelineState = nullptr;
    void* radixPrefixPipelineState = nullptr;
    void* radixReorderPipelineState = nullptr;
};

MetalGaussianSortPass::MetalGaussianSortPass()
    : m_impl(std::make_unique<Impl>())
{
}

MetalGaussianSortPass::~MetalGaussianSortPass() = default;

MetalGaussianSortPass::MetalGaussianSortPass(MetalGaussianSortPass&&) noexcept = default;

MetalGaussianSortPass& MetalGaussianSortPass::operator=(MetalGaussianSortPass&&) noexcept = default;

bool MetalGaussianSortPass::initialize(
    MetalShaderLibrary& shaderLibrary,
    MetalPipelineCache& pipelineCache,
    std::string* errorMessage)
{
    auto createPipeline = [&shaderLibrary, &pipelineCache, errorMessage](
                              const MetalComputePipelineDesc& pipelineDesc,
                              void*& pipelineState) -> bool {
        std::string pipelineError;
        pipelineState = pipelineCache.computePipeline(shaderLibrary, pipelineDesc, &pipelineError);
        if (pipelineState != nullptr) {
            return true;
        }

        if (errorMessage != nullptr) {
            *errorMessage = "Failed to initialize gaussian sort compute pipeline '" + pipelineDesc.label + "'";
            if (!pipelineError.empty()) {
                *errorMessage += ": " + pipelineError;
            }
        }
        return false;
    };

    MetalComputePipelineDesc desc;
    desc.label = "Gaussian Depth Key Pipeline";
    desc.function = "gaussianDepthKeyKernel";
    if (!createPipeline(desc, m_impl->depthKeyPipelineState)) {
        return false;
    }

    MetalComputePipelineDesc countDesc;
    countDesc.label = "Gaussian Radix Count Pipeline";
    countDesc.function = "gaussianRadixCountKernel";
    if (!createPipeline(countDesc, m_impl->radixCountPipelineState)) {
        return false;
    }

    MetalComputePipelineDesc prefixDesc;
    prefixDesc.label = "Gaussian Radix Prefix Pipeline";
    prefixDesc.function = "gaussianRadixPrefixKernel";
    if (!createPipeline(prefixDesc, m_impl->radixPrefixPipelineState)) {
        return false;
    }

    MetalComputePipelineDesc reorderDesc;
    reorderDesc.label = "Gaussian Radix Reorder Pipeline";
    reorderDesc.function = "gaussianRadixReorderKernel";
    if (!createPipeline(reorderDesc, m_impl->radixReorderPipelineState)) {
        return false;
    }

    if (errorMessage != nullptr) {
        errorMessage->clear();
    }
    return true;
}

bool MetalGaussianSortPass::isReady() const
{
    return m_impl->depthKeyPipelineState != nullptr &&
        m_impl->radixCountPipelineState != nullptr &&
        m_impl->radixPrefixPipelineState != nullptr &&
        m_impl->radixReorderPipelineState != nullptr;
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
    id<MTLComputePipelineState> radixCountPipelineState =
        (__bridge id<MTLComputePipelineState>)m_impl->radixCountPipelineState;
    id<MTLComputePipelineState> radixPrefixPipelineState =
        (__bridge id<MTLComputePipelineState>)m_impl->radixPrefixPipelineState;
    id<MTLComputePipelineState> radixReorderPipelineState =
        (__bridge id<MTLComputePipelineState>)m_impl->radixReorderPipelineState;
    id<MTLBuffer> gaussianBufferHandle = (__bridge id<MTLBuffer>)gaussianBuffer.nativeBuffer();
    id<MTLBuffer> frameBuffer = (__bridge id<MTLBuffer>)frameUniformBuffer;
    id<MTLBuffer> keyBuffer = (__bridge id<MTLBuffer>)sortBuffer.nativeKeyBuffer();
    id<MTLBuffer> indexBuffer = (__bridge id<MTLBuffer>)sortBuffer.nativeIndexBuffer();
    id<MTLBuffer> scratchKeyBuffer = (__bridge id<MTLBuffer>)sortBuffer.nativeScratchKeyBuffer();
    id<MTLBuffer> scratchIndexBuffer = (__bridge id<MTLBuffer>)sortBuffer.nativeScratchIndexBuffer();
    id<MTLBuffer> blockCountBuffer = (__bridge id<MTLBuffer>)sortBuffer.nativeBlockCountBuffer();
    id<MTLBuffer> globalOffsetBuffer = (__bridge id<MTLBuffer>)sortBuffer.nativeGlobalOffsetBuffer();
    if (nativeCommandBuffer == nil || pipelineState == nil || radixCountPipelineState == nil ||
        radixPrefixPipelineState == nil || radixReorderPipelineState == nil ||
        gaussianBufferHandle == nil || frameBuffer == nil || keyBuffer == nil || indexBuffer == nil ||
        scratchKeyBuffer == nil || scratchIndexBuffer == nil || blockCountBuffer == nil ||
        globalOffsetBuffer == nil) {
        return false;
    }

    if (sortBuffer.capacity() > static_cast<std::size_t>(UINT32_MAX) ||
        sortBuffer.blockCount() > static_cast<std::size_t>(UINT32_MAX) ||
        !sortBuffer.setCount(gaussianBuffer.count())) {
        return false;
    }

    if (radixCountPipelineState.maxTotalThreadsPerThreadgroup < kRadixSortThreadCount ||
        radixReorderPipelineState.maxTotalThreadsPerThreadgroup < kRadixSortThreadCount ||
        radixPrefixPipelineState.maxTotalThreadsPerThreadgroup < kRadixBinCount) {
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

    const NSUInteger threadsPerGroup =
        static_cast<NSUInteger>(computeThreadgroupSize1D((__bridge void*)pipelineState));
    [encoder dispatchThreads:MTLSizeMake(gaussianBuffer.count(), 1, 1)
       threadsPerThreadgroup:MTLSizeMake(threadsPerGroup, 1, 1)];
    [encoder endEncoding];

    if (gaussianBuffer.count() <= 1) {
        return true;
    }

    RadixSortParams sortParams;
    sortParams.itemCount = gaussianBuffer.count();
    const uint32_t activeBlockCount =
        (gaussianBuffer.count() + kRadixSortThreadCount - 1) / kRadixSortThreadCount;
    if (activeBlockCount == 0 || activeBlockCount > sortBuffer.blockCount()) {
        return false;
    }
    sortParams.blockCount = activeBlockCount;

    const NSRange blockCountRange =
        NSMakeRange(0, static_cast<std::size_t>(activeBlockCount) * kRadixBinCount * sizeof(uint32_t));
    const NSRange globalOffsetRange = NSMakeRange(0, kRadixBinCount * sizeof(uint32_t));
    const MTLSize sortThreadgroups = MTLSizeMake(activeBlockCount, 1, 1);
    const MTLSize sortThreadsPerThreadgroup = MTLSizeMake(kRadixSortThreadCount, 1, 1);
    const MTLSize prefixThreads = MTLSizeMake(kRadixBinCount, 1, 1);

    id<MTLBuffer> sourceKeyBuffer = keyBuffer;
    id<MTLBuffer> sourceIndexBuffer = indexBuffer;
    id<MTLBuffer> destinationKeyBuffer = scratchKeyBuffer;
    id<MTLBuffer> destinationIndexBuffer = scratchIndexBuffer;
    for (uint32_t passIndex = 0; passIndex < kRadixPassCount; ++passIndex) {
        sortParams.radixShift = passIndex * 4;

        id<MTLBlitCommandEncoder> blitEncoder = [nativeCommandBuffer blitCommandEncoder];
        if (blitEncoder == nil) {
            return false;
        }
        blitEncoder.label = @"Mesh2Splat Gaussian Radix Clear";
        [blitEncoder fillBuffer:blockCountBuffer range:blockCountRange value:0];
        [blitEncoder fillBuffer:globalOffsetBuffer range:globalOffsetRange value:0];
        [blitEncoder endEncoding];

        id<MTLComputeCommandEncoder> countEncoder = [nativeCommandBuffer computeCommandEncoder];
        if (countEncoder == nil) {
            return false;
        }
        countEncoder.label = @"Mesh2Splat Gaussian Radix Count";
        [countEncoder setComputePipelineState:radixCountPipelineState];
        [countEncoder setBuffer:sourceKeyBuffer offset:0 atIndex:0];
        [countEncoder setBuffer:blockCountBuffer offset:0 atIndex:1];
        [countEncoder setBuffer:globalOffsetBuffer offset:0 atIndex:2];
        [countEncoder setBytes:&sortParams length:sizeof(sortParams) atIndex:3];
        [countEncoder dispatchThreadgroups:sortThreadgroups threadsPerThreadgroup:sortThreadsPerThreadgroup];
        [countEncoder endEncoding];

        id<MTLComputeCommandEncoder> prefixEncoder = [nativeCommandBuffer computeCommandEncoder];
        if (prefixEncoder == nil) {
            return false;
        }
        prefixEncoder.label = @"Mesh2Splat Gaussian Radix Prefix";
        [prefixEncoder setComputePipelineState:radixPrefixPipelineState];
        [prefixEncoder setBuffer:blockCountBuffer offset:0 atIndex:0];
        [prefixEncoder setBuffer:globalOffsetBuffer offset:0 atIndex:1];
        [prefixEncoder setBytes:&sortParams length:sizeof(sortParams) atIndex:2];
        [prefixEncoder dispatchThreads:prefixThreads threadsPerThreadgroup:prefixThreads];
        [prefixEncoder endEncoding];

        id<MTLComputeCommandEncoder> reorderEncoder = [nativeCommandBuffer computeCommandEncoder];
        if (reorderEncoder == nil) {
            return false;
        }
        reorderEncoder.label = @"Mesh2Splat Gaussian Radix Reorder";
        [reorderEncoder setComputePipelineState:radixReorderPipelineState];
        [reorderEncoder setBuffer:sourceKeyBuffer offset:0 atIndex:0];
        [reorderEncoder setBuffer:sourceIndexBuffer offset:0 atIndex:1];
        [reorderEncoder setBuffer:destinationKeyBuffer offset:0 atIndex:2];
        [reorderEncoder setBuffer:destinationIndexBuffer offset:0 atIndex:3];
        [reorderEncoder setBuffer:blockCountBuffer offset:0 atIndex:4];
        [reorderEncoder setBuffer:globalOffsetBuffer offset:0 atIndex:5];
        [reorderEncoder setBytes:&sortParams length:sizeof(sortParams) atIndex:6];
        [reorderEncoder dispatchThreadgroups:sortThreadgroups threadsPerThreadgroup:sortThreadsPerThreadgroup];
        [reorderEncoder endEncoding];

        std::swap(sourceKeyBuffer, destinationKeyBuffer);
        std::swap(sourceIndexBuffer, destinationIndexBuffer);
    }

    return true;
}

} // namespace mesh2splat::metal
