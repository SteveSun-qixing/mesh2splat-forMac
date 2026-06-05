#include "MetalConversionPass.hpp"

#include "MetalGaussianBuffer.hpp"
#include "MetalMesh.hpp"
#include "MetalPipelineCache.hpp"
#include "MetalSceneResources.hpp"
#include "MetalShaderLibrary.hpp"

#import <Metal/Metal.h>

#include <algorithm>
#include <cstdint>

namespace mesh2splat::metal {
namespace {

struct MeshConversionParams {
    uint32_t vertexOffset = 0;
    uint32_t triangleCount = 0;
    uint32_t materialIndex = 0;
    uint32_t maxGaussianCount = 0;
    float gaussianScale = 1.0f;
    float normalScale = 1.0f;
    uint32_t flags = 0;
    uint32_t reserved = 0;
};

static_assert(sizeof(MeshConversionParams) == 32, "MeshConversionParams must match the Metal shader layout.");

} // namespace

struct MetalConversionPass::Impl {
    void* computePipelineState = nullptr;
};

MetalConversionPass::MetalConversionPass()
    : m_impl(std::make_unique<Impl>())
{
}

MetalConversionPass::~MetalConversionPass() = default;

MetalConversionPass::MetalConversionPass(MetalConversionPass&&) noexcept = default;

MetalConversionPass& MetalConversionPass::operator=(MetalConversionPass&&) noexcept = default;

bool MetalConversionPass::initialize(MetalShaderLibrary& shaderLibrary, MetalPipelineCache& pipelineCache)
{
    MetalComputePipelineDesc pipelineDesc;
    pipelineDesc.label = "Mesh Vertex Conversion Pipeline";
    pipelineDesc.function = "meshVertexConversionKernel";
    m_impl->computePipelineState = pipelineCache.computePipeline(shaderLibrary, pipelineDesc);
    return m_impl->computePipelineState != nullptr;
}

bool MetalConversionPass::isReady() const
{
    return m_impl->computePipelineState != nullptr;
}

bool MetalConversionPass::encode(
    void* commandBuffer,
    const MetalSceneResources& sceneResources,
    MetalGaussianBuffer& gaussianBuffer) const
{
    if (!isReady() || commandBuffer == nullptr || !sceneResources.isValid() || !gaussianBuffer.isValid()) {
        return false;
    }

    id<MTLCommandBuffer> nativeCommandBuffer = (__bridge id<MTLCommandBuffer>)commandBuffer;
    id<MTLComputePipelineState> pipelineState =
        (__bridge id<MTLComputePipelineState>)m_impl->computePipelineState;
    id<MTLBuffer> outputBuffer = (__bridge id<MTLBuffer>)gaussianBuffer.nativeBuffer();
    id<MTLBuffer> counterBuffer = (__bridge id<MTLBuffer>)gaussianBuffer.nativeCounterBuffer();
    if (nativeCommandBuffer == nil || pipelineState == nil || outputBuffer == nil || counterBuffer == nil ||
        gaussianBuffer.capacity() > static_cast<std::size_t>(UINT32_MAX) || !gaussianBuffer.resetGpuCounter()) {
        return false;
    }

    id<MTLComputeCommandEncoder> encoder = [nativeCommandBuffer computeCommandEncoder];
    if (encoder == nil) {
        return false;
    }

    encoder.label = @"Mesh2Splat Mesh Vertex Conversion";
    [encoder setComputePipelineState:pipelineState];
    [encoder setBuffer:outputBuffer offset:0 atIndex:2];
    [encoder setBuffer:counterBuffer offset:0 atIndex:4];

    const NSUInteger threadExecutionWidth = std::max<NSUInteger>(1, pipelineState.threadExecutionWidth);
    const NSUInteger maxThreads = std::max<NSUInteger>(1, pipelineState.maxTotalThreadsPerThreadgroup);
    const NSUInteger threadsPerGroup = std::min<NSUInteger>(threadExecutionWidth, maxThreads);

    for (std::size_t meshIndex = 0; meshIndex < sceneResources.meshCount(); ++meshIndex) {
        const MetalMesh* mesh = sceneResources.meshAt(meshIndex);
        if (mesh == nullptr || !mesh->isValid()) {
            continue;
        }

        id<MTLBuffer> vertexBuffer = (__bridge id<MTLBuffer>)mesh->vertexBuffer();
        id<MTLBuffer> materialBuffer = (__bridge id<MTLBuffer>)mesh->materialBuffer();
        if (vertexBuffer == nil || materialBuffer == nil) {
            continue;
        }

        [encoder setBuffer:vertexBuffer offset:0 atIndex:0];
        [encoder setBuffer:materialBuffer offset:0 atIndex:1];

        for (uint32_t rangeIndex = 0; rangeIndex < mesh->drawRangeCount(); ++rangeIndex) {
            const MetalMeshDrawRange* range = mesh->drawRange(rangeIndex);
            if (range == nullptr || range->vertexCount == 0 || range->vertexCount % 3 != 0 ||
                range->materialIndex >= mesh->materialCount()) {
                continue;
            }

            const uint32_t triangleCount = range->vertexCount / 3;
            MeshConversionParams params;
            params.vertexOffset = range->vertexOffset;
            params.triangleCount = triangleCount;
            params.materialIndex = range->materialIndex;
            params.maxGaussianCount = static_cast<uint32_t>(gaussianBuffer.capacity());
            params.gaussianScale = 0.33f;
            params.normalScale = 1.0f;

            [encoder setBytes:&params length:sizeof(params) atIndex:3];
            const MTLSize gridSize = MTLSizeMake(triangleCount, 1, 1);
            const MTLSize threadgroupSize = MTLSizeMake(threadsPerGroup, 1, 1);
            [encoder dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
        }
    }

    [encoder endEncoding];
    return true;
}

} // namespace mesh2splat::metal
