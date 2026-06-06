#include "MetalConversionPass.hpp"

#include "MetalGaussianBuffer.hpp"
#include "MetalDispatchUtils.hpp"
#include "MetalMesh.hpp"
#include "MetalPipelineCache.hpp"
#include "MetalRenderStateCache.hpp"
#include "MetalSceneResources.hpp"
#include "MetalShaderLibrary.hpp"

#import <Metal/Metal.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>

namespace mesh2splat::metal {
namespace {

struct MeshConversionParams {
    uint32_t vertexOffset = 0;
    uint32_t triangleCount = 0;
    uint32_t materialIndex = 0;
    uint32_t maxGaussianCount = 0;
    float gaussianScale = 1.0f;
    float normalScale = 1.0f;
    float areaSampleDensity = 0.0f;
    uint32_t maxSamplesPerTriangle = 1;
};

static_assert(sizeof(MeshConversionParams) == 32, "MeshConversionParams must match the Metal shader layout.");

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

} // namespace

struct MetalConversionPass::Impl {
    void* computePipelineState = nullptr;
    void* samplerState = nullptr;
};

MetalConversionPass::MetalConversionPass()
    : m_impl(std::make_unique<Impl>())
{
}

MetalConversionPass::~MetalConversionPass() = default;

MetalConversionPass::MetalConversionPass(MetalConversionPass&&) noexcept = default;

MetalConversionPass& MetalConversionPass::operator=(MetalConversionPass&&) noexcept = default;

bool MetalConversionPass::initialize(
    MetalShaderLibrary& shaderLibrary,
    MetalPipelineCache& pipelineCache,
    MetalRenderStateCache& renderStateCache)
{
    MetalComputePipelineDesc pipelineDesc;
    pipelineDesc.label = "Mesh Vertex Conversion Pipeline";
    pipelineDesc.function = "meshVertexConversionKernel";
    m_impl->computePipelineState = pipelineCache.computePipeline(shaderLibrary, pipelineDesc);
    if (m_impl->computePipelineState == nullptr) {
        return false;
    }

    MetalSamplerDesc samplerDesc;
    samplerDesc.label = "Mesh Conversion Texture Sampler";
    samplerDesc.minFilter = MetalSamplerFilter::Linear;
    samplerDesc.magFilter = MetalSamplerFilter::Linear;
    samplerDesc.mipFilter = MetalSamplerFilter::Linear;
    samplerDesc.addressU = MetalSamplerAddressMode::Repeat;
    samplerDesc.addressV = MetalSamplerAddressMode::Repeat;
    samplerDesc.addressW = MetalSamplerAddressMode::Repeat;
    m_impl->samplerState = renderStateCache.samplerState(samplerDesc);
    return m_impl->samplerState != nullptr;
}

bool MetalConversionPass::isReady() const
{
    return m_impl->computePipelineState != nullptr && m_impl->samplerState != nullptr;
}

bool MetalConversionPass::encode(
    void* commandBuffer,
    const MetalSceneResources& sceneResources,
    MetalGaussianBuffer& gaussianBuffer,
    uint32_t samplesPerTriangle) const
{
    if (!isReady() || commandBuffer == nullptr || !sceneResources.isValid() || !gaussianBuffer.isValid()) {
        return false;
    }

    id<MTLCommandBuffer> nativeCommandBuffer = (__bridge id<MTLCommandBuffer>)commandBuffer;
    id<MTLComputePipelineState> pipelineState =
        (__bridge id<MTLComputePipelineState>)m_impl->computePipelineState;
    id<MTLSamplerState> samplerState = (__bridge id<MTLSamplerState>)m_impl->samplerState;
    id<MTLBuffer> outputBuffer = (__bridge id<MTLBuffer>)gaussianBuffer.nativeBuffer();
    id<MTLBuffer> counterBuffer = (__bridge id<MTLBuffer>)gaussianBuffer.nativeCounterBuffer();
    if (nativeCommandBuffer == nil || pipelineState == nil || samplerState == nil ||
        outputBuffer == nil || counterBuffer == nil ||
        gaussianBuffer.capacity() > static_cast<std::size_t>(UINT32_MAX) ||
        !gaussianBuffer.encodeResetGpuCounter(commandBuffer)) {
        return false;
    }

    id<MTLComputeCommandEncoder> encoder = [nativeCommandBuffer computeCommandEncoder];
    if (encoder == nil) {
        return false;
    }

    encoder.label = @"Mesh2Splat Mesh Vertex Conversion";
    [encoder setComputePipelineState:pipelineState];
    [encoder setSamplerState:samplerState atIndex:0];
    [encoder setBuffer:outputBuffer offset:0 atIndex:2];
    [encoder setBuffer:counterBuffer offset:0 atIndex:4];

    const NSUInteger threadsPerGroup =
        static_cast<NSUInteger>(computeThreadgroupSize1D((__bridge void*)pipelineState));
    const uint32_t sampleCount = normalizedSamplesPerTriangle(samplesPerTriangle);

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

            id<MTLTexture> baseColorTexture = (__bridge id<MTLTexture>)mesh->baseColorTexture(range->materialIndex);
            id<MTLTexture> metallicRoughnessTexture =
                (__bridge id<MTLTexture>)mesh->metallicRoughnessTexture(range->materialIndex);
            id<MTLTexture> normalTexture = (__bridge id<MTLTexture>)mesh->normalTexture(range->materialIndex);
            id<MTLTexture> occlusionTexture = (__bridge id<MTLTexture>)mesh->occlusionTexture(range->materialIndex);
            id<MTLTexture> emissiveTexture = (__bridge id<MTLTexture>)mesh->emissiveTexture(range->materialIndex);
            if (baseColorTexture == nil || metallicRoughnessTexture == nil || normalTexture == nil ||
                occlusionTexture == nil || emissiveTexture == nil) {
                continue;
            }

            [encoder setTexture:baseColorTexture atIndex:0];
            [encoder setTexture:metallicRoughnessTexture atIndex:1];
            [encoder setTexture:normalTexture atIndex:2];
            [encoder setTexture:occlusionTexture atIndex:3];
            [encoder setTexture:emissiveTexture atIndex:4];

            const uint32_t triangleCount = range->vertexCount / 3;
            MeshConversionParams params;
            params.vertexOffset = range->vertexOffset;
            params.triangleCount = triangleCount;
            params.materialIndex = range->materialIndex;
            params.maxGaussianCount = static_cast<uint32_t>(gaussianBuffer.capacity());
            params.gaussianScale = 0.22f;
            params.normalScale = 1.0f;
            params.areaSampleDensity = areaSampleDensity(*range, triangleCount, sampleCount);
            params.maxSamplesPerTriangle = sampleCount;

            [encoder setBytes:&params length:sizeof(params) atIndex:3];
            const MTLSize gridSize = MTLSizeMake(triangleCount * sampleCount, 1, 1);
            const MTLSize threadgroupSize = MTLSizeMake(threadsPerGroup, 1, 1);
            [encoder dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
        }
    }

    [encoder endEncoding];
    return gaussianBuffer.encodeReadbackGpuCounter(commandBuffer);
}

} // namespace mesh2splat::metal
