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
#include <limits>
#include <string>
#include <utility>

namespace mesh2splat::metal {
namespace {

struct GaussianSortParams {
    uint32_t gaussianCount = 0;
    uint32_t keyCapacity = 0;
    uint32_t indexCapacity = 0;
    uint32_t reserved = 0;
};

struct RadixSortParams {
    uint32_t itemCount = 0;
    uint32_t blockCount = 0;
    uint32_t radixShift = 0;
    uint32_t outputCapacity = 0;
};

static_assert(sizeof(GaussianSortParams) == 16, "GaussianSortParams must match the Metal shader layout.");
static_assert(sizeof(RadixSortParams) == 16, "RadixSortParams must match the Metal shader layout.");

constexpr uint32_t kRadixBinCount = 16;
constexpr uint32_t kRadixPassCount = 8;
constexpr uint32_t kRadixSortThreadCount = 256;
constexpr const char* kSortBufferLabel = "Mesh2Splat Gaussian Sort";

uint32_t radixBlockCount(uint32_t itemCount)
{
    const std::size_t count = itemCount;
    return static_cast<uint32_t>((count + kRadixSortThreadCount - 1) / kRadixSortThreadCount);
}

std::string sortBufferStatsDescription(const MetalGaussianSortBuffer& sortBuffer)
{
    const MetalGaussianSortBuffer::ResourceStats stats = sortBuffer.resourceStats();
    return "sort capacity=" + std::to_string(stats.capacity) +
        ", active count=" + std::to_string(stats.count) +
        ", radix blocks=" + std::to_string(stats.blockCount) +
        ", resources bytes={keys=" + std::to_string(stats.keyBytes) +
        ", indices=" + std::to_string(stats.indexBytes) +
        ", scratchKeys=" + std::to_string(stats.scratchKeyBytes) +
        ", scratchIndices=" + std::to_string(stats.scratchIndexBytes) +
        ", blockCounts=" + std::to_string(stats.blockCountBytes) +
        ", globalOffsets=" + std::to_string(stats.globalOffsetBytes) +
        ", total=" + std::to_string(stats.totalBytes) + "}";
}

} // namespace

struct MetalGaussianSortPass::Impl {
    void* identityIndexPipelineState = nullptr;
    void* depthKeyPipelineState = nullptr;
    void* radixCountPipelineState = nullptr;
    void* radixPrefixPipelineState = nullptr;
    void* radixReorderPipelineState = nullptr;
    std::string lastDiagnostic;
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
    desc.label = "Gaussian Identity Index Pipeline";
    desc.function = "gaussianIdentityIndexKernel";
    if (!createPipeline(desc, m_impl->identityIndexPipelineState)) {
        return false;
    }

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
    return m_impl->identityIndexPipelineState != nullptr &&
        m_impl->depthKeyPipelineState != nullptr &&
        m_impl->radixCountPipelineState != nullptr &&
        m_impl->radixPrefixPipelineState != nullptr &&
        m_impl->radixReorderPipelineState != nullptr;
}

const std::string& MetalGaussianSortPass::lastDiagnostic() const
{
    return m_impl->lastDiagnostic;
}

bool MetalGaussianSortPass::encodeDepthKeys(
    void* commandBuffer,
    const MetalGaussianBuffer& gaussianBuffer,
    MetalGaussianSortBuffer& sortBuffer,
    void* frameUniformBuffer) const
{
    m_impl->lastDiagnostic.clear();
    const auto fail = [this](std::string message) {
        m_impl->lastDiagnostic = std::move(message);
        return false;
    };

    if (!isReady()) {
        return fail("Gaussian sort pass is not initialized.");
    }

    if (commandBuffer == nullptr) {
        return fail("Gaussian sort pass cannot encode without a command buffer.");
    }

    if (frameUniformBuffer == nullptr) {
        return fail("Gaussian sort pass cannot encode depth keys without frame uniforms.");
    }

    if (!gaussianBuffer.isValid()) {
        return fail("Gaussian sort pass received an invalid gaussian buffer.");
    }

    const uint32_t gaussianCount = gaussianBuffer.count();
    if (gaussianCount == 0) {
        sortBuffer.setCount(0);
        return true;
    }

    if (!sortBuffer.ensureCapacity(gaussianCount, kSortBufferLabel)) {
        sortBuffer.setCount(0);
        return fail("Gaussian sort buffer could not grow for " +
            std::to_string(gaussianCount) + " gaussians: " +
            sortBufferStatsDescription(sortBuffer));
    }

    if (!sortBuffer.isValid()) {
        sortBuffer.setCount(0);
        return fail("Gaussian sort pass received an invalid sort buffer after capacity check: " +
            sortBufferStatsDescription(sortBuffer));
    }

    if (!sortBuffer.hasCapacityFor(gaussianCount)) {
        sortBuffer.setCount(0);
        return fail("Gaussian sort buffer capacity is too small for " +
            std::to_string(gaussianCount) + " gaussians: " +
            sortBufferStatsDescription(sortBuffer));
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
    if (nativeCommandBuffer == nil) {
        return fail("Gaussian sort pass command buffer bridge returned nil.");
    }

    if (pipelineState == nil || radixCountPipelineState == nil || radixPrefixPipelineState == nil ||
        radixReorderPipelineState == nil) {
        return fail("Gaussian sort pass has a nil Metal pipeline state.");
    }

    if (gaussianBufferHandle == nil || frameBuffer == nil || keyBuffer == nil || indexBuffer == nil ||
        scratchKeyBuffer == nil || scratchIndexBuffer == nil || blockCountBuffer == nil ||
        globalOffsetBuffer == nil) {
        return fail("Gaussian sort pass has a nil Metal buffer binding: " +
            sortBufferStatsDescription(sortBuffer));
    }

    if (sortBuffer.capacity() > static_cast<std::size_t>(std::numeric_limits<uint32_t>::max()) ||
        sortBuffer.blockCount() > static_cast<std::size_t>(std::numeric_limits<uint32_t>::max())) {
        return fail("Gaussian sort buffer exceeds 32-bit Metal sort parameters: " +
            sortBufferStatsDescription(sortBuffer));
    }

    if (!sortBuffer.setCount(gaussianCount)) {
        return fail("Gaussian sort buffer rejected active count " +
            std::to_string(gaussianCount) + ": " +
            sortBufferStatsDescription(sortBuffer));
    }

    if (radixCountPipelineState.maxTotalThreadsPerThreadgroup < kRadixSortThreadCount ||
        radixReorderPipelineState.maxTotalThreadsPerThreadgroup < kRadixSortThreadCount ||
        radixPrefixPipelineState.maxTotalThreadsPerThreadgroup < kRadixBinCount) {
        return fail("Gaussian radix sort pipeline threadgroup limit is smaller than the shader contract.");
    }

    id<MTLComputeCommandEncoder> encoder = [nativeCommandBuffer computeCommandEncoder];
    if (encoder == nil) {
        return fail("Failed to create gaussian depth key compute encoder.");
    }

    encoder.label = @"Mesh2Splat Gaussian Depth Keys";
    [encoder setComputePipelineState:pipelineState];
    [encoder setBuffer:gaussianBufferHandle offset:0 atIndex:0];
    [encoder setBuffer:frameBuffer offset:0 atIndex:1];
    [encoder setBuffer:keyBuffer offset:0 atIndex:2];
    [encoder setBuffer:indexBuffer offset:0 atIndex:3];

    GaussianSortParams params;
    params.gaussianCount = gaussianCount;
    params.keyCapacity = static_cast<uint32_t>(sortBuffer.capacity());
    params.indexCapacity = static_cast<uint32_t>(sortBuffer.capacity());
    [encoder setBytes:&params length:sizeof(params) atIndex:4];

    const NSUInteger threadsPerGroup =
        static_cast<NSUInteger>(computeThreadgroupSize1D((__bridge void*)pipelineState));
    [encoder dispatchThreads:MTLSizeMake(gaussianCount, 1, 1)
       threadsPerThreadgroup:MTLSizeMake(threadsPerGroup, 1, 1)];
    [encoder endEncoding];

    if (gaussianCount <= 1) {
        return true;
    }

    RadixSortParams sortParams;
    sortParams.itemCount = gaussianCount;
    sortParams.outputCapacity = static_cast<uint32_t>(sortBuffer.capacity());
    const uint32_t activeBlockCount = radixBlockCount(gaussianCount);
    if (activeBlockCount == 0 || activeBlockCount > sortBuffer.blockCount()) {
        return fail("Gaussian radix active block count is outside sort buffer capacity: active blocks=" +
            std::to_string(activeBlockCount) + ", " + sortBufferStatsDescription(sortBuffer));
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
            return fail("Failed to create gaussian radix clear blit encoder for pass " +
                std::to_string(passIndex) + ".");
        }
        blitEncoder.label = [NSString stringWithFormat:@"Mesh2Splat Gaussian Radix Clear Pass %u", passIndex];
        [blitEncoder fillBuffer:blockCountBuffer range:blockCountRange value:0];
        [blitEncoder fillBuffer:globalOffsetBuffer range:globalOffsetRange value:0];
        [blitEncoder endEncoding];

        id<MTLComputeCommandEncoder> countEncoder = [nativeCommandBuffer computeCommandEncoder];
        if (countEncoder == nil) {
            return fail("Failed to create gaussian radix count encoder for pass " +
                std::to_string(passIndex) + ".");
        }
        countEncoder.label = [NSString stringWithFormat:@"Mesh2Splat Gaussian Radix Count Pass %u", passIndex];
        [countEncoder setComputePipelineState:radixCountPipelineState];
        [countEncoder setBuffer:sourceKeyBuffer offset:0 atIndex:0];
        [countEncoder setBuffer:blockCountBuffer offset:0 atIndex:1];
        [countEncoder setBuffer:globalOffsetBuffer offset:0 atIndex:2];
        [countEncoder setBytes:&sortParams length:sizeof(sortParams) atIndex:3];
        [countEncoder dispatchThreadgroups:sortThreadgroups threadsPerThreadgroup:sortThreadsPerThreadgroup];
        [countEncoder endEncoding];

        id<MTLComputeCommandEncoder> prefixEncoder = [nativeCommandBuffer computeCommandEncoder];
        if (prefixEncoder == nil) {
            return fail("Failed to create gaussian radix prefix encoder for pass " +
                std::to_string(passIndex) + ".");
        }
        prefixEncoder.label = [NSString stringWithFormat:@"Mesh2Splat Gaussian Radix Prefix Pass %u", passIndex];
        [prefixEncoder setComputePipelineState:radixPrefixPipelineState];
        [prefixEncoder setBuffer:blockCountBuffer offset:0 atIndex:0];
        [prefixEncoder setBuffer:globalOffsetBuffer offset:0 atIndex:1];
        [prefixEncoder setBytes:&sortParams length:sizeof(sortParams) atIndex:2];
        [prefixEncoder dispatchThreads:prefixThreads threadsPerThreadgroup:prefixThreads];
        [prefixEncoder endEncoding];

        id<MTLComputeCommandEncoder> reorderEncoder = [nativeCommandBuffer computeCommandEncoder];
        if (reorderEncoder == nil) {
            return fail("Failed to create gaussian radix reorder encoder for pass " +
                std::to_string(passIndex) + ".");
        }
        reorderEncoder.label = [NSString stringWithFormat:@"Mesh2Splat Gaussian Radix Reorder Pass %u", passIndex];
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

bool MetalGaussianSortPass::encodeIdentityIndices(
    void* commandBuffer,
    const MetalGaussianBuffer& gaussianBuffer,
    MetalGaussianSortBuffer& sortBuffer) const
{
    m_impl->lastDiagnostic.clear();
    const auto fail = [this](std::string message) {
        m_impl->lastDiagnostic = std::move(message);
        return false;
    };

    if (m_impl->identityIndexPipelineState == nullptr) {
        return fail("Gaussian identity index pass is not initialized.");
    }
    if (commandBuffer == nullptr) {
        return fail("Gaussian identity index pass cannot encode without a command buffer.");
    }
    if (!gaussianBuffer.isValid()) {
        return fail("Gaussian identity index pass received an invalid gaussian buffer.");
    }

    const uint32_t gaussianCount = gaussianBuffer.count();
    if (gaussianCount == 0) {
        sortBuffer.setCount(0);
        return true;
    }

    if (!sortBuffer.ensureCapacity(gaussianCount, kSortBufferLabel)) {
        sortBuffer.setCount(0);
        return fail("Gaussian sort buffer could not grow for identity indices for " +
            std::to_string(gaussianCount) + " gaussians: " +
            sortBufferStatsDescription(sortBuffer));
    }

    if (!sortBuffer.isValid()) {
        sortBuffer.setCount(0);
        return fail("Gaussian identity index pass received an invalid sort buffer: " +
            sortBufferStatsDescription(sortBuffer));
    }

    if (!sortBuffer.hasCapacityFor(gaussianCount)) {
        sortBuffer.setCount(0);
        return fail("Gaussian identity index buffer capacity is too small for " +
            std::to_string(gaussianCount) + " gaussians: " +
            sortBufferStatsDescription(sortBuffer));
    }

    if (!sortBuffer.setCount(gaussianCount)) {
        return fail("Gaussian identity index buffer rejected active count " +
            std::to_string(gaussianCount) + ": " +
            sortBufferStatsDescription(sortBuffer));
    }

    id<MTLCommandBuffer> nativeCommandBuffer = (__bridge id<MTLCommandBuffer>)commandBuffer;
    id<MTLComputePipelineState> pipelineState =
        (__bridge id<MTLComputePipelineState>)m_impl->identityIndexPipelineState;
    id<MTLBuffer> indexBuffer = (__bridge id<MTLBuffer>)sortBuffer.nativeIndexBuffer();
    id<MTLBuffer> keyBuffer = (__bridge id<MTLBuffer>)sortBuffer.nativeKeyBuffer();
    if (nativeCommandBuffer == nil) {
        return fail("Gaussian identity index command buffer bridge returned nil.");
    }
    if (pipelineState == nil) {
        return fail("Gaussian identity index pass has a nil Metal pipeline state.");
    }
    if (indexBuffer == nil || keyBuffer == nil) {
        return fail("Gaussian identity index pass has a nil Metal buffer binding: " +
            sortBufferStatsDescription(sortBuffer));
    }

    id<MTLComputeCommandEncoder> encoder = [nativeCommandBuffer computeCommandEncoder];
    if (encoder == nil) {
        return fail("Failed to create gaussian identity index compute encoder.");
    }

    GaussianSortParams params;
    params.gaussianCount = gaussianCount;
    params.keyCapacity = static_cast<uint32_t>(sortBuffer.capacity());
    params.indexCapacity = static_cast<uint32_t>(sortBuffer.capacity());

    encoder.label = @"Mesh2Splat Gaussian Identity Indices";
    [encoder setComputePipelineState:pipelineState];
    [encoder setBuffer:indexBuffer offset:0 atIndex:0];
    [encoder setBuffer:keyBuffer offset:0 atIndex:1];
    [encoder setBytes:&params length:sizeof(params) atIndex:2];
    const NSUInteger threadsPerGroup =
        static_cast<NSUInteger>(computeThreadgroupSize1D((__bridge void*)pipelineState));
    [encoder dispatchThreads:MTLSizeMake(gaussianCount, 1, 1)
       threadsPerThreadgroup:MTLSizeMake(threadsPerGroup, 1, 1)];
    [encoder endEncoding];
    return true;
}

} // namespace mesh2splat::metal
