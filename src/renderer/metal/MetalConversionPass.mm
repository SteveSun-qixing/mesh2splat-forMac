#include "MetalConversionPass.hpp"

#include "core/GaussianData.hpp"
#include "core/GpuTypes.hpp"
#include "core/MeshData.hpp"
#include "MetalBindings.hpp"
#include "MetalGaussianBuffer.hpp"
#include "MetalDispatchUtils.hpp"
#include "MetalMesh.hpp"
#include "MetalPipelineCache.hpp"
#include "MetalRenderStateCache.hpp"
#include "MetalSceneResources.hpp"
#include "MetalShaderLibrary.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <string>
#include <type_traits>
#include <utility>

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
static_assert(
    std::is_standard_layout<MeshConversionParams>::value,
    "MeshConversionParams must remain a plain constant-buffer layout.");
static_assert(sizeof(MetalMeshMaterial) == 48, "MetalMeshMaterial must match the Metal conversion shader layout.");
static_assert(
    std::is_standard_layout<MetalMeshMaterial>::value,
    "MetalMeshMaterial must remain a plain Metal buffer layout.");
static_assert(
    sizeof(core::GaussianRecord) == sizeof(float) * 4 * 6,
    "Metal conversion output expects GaussianRecord to remain six float4 slots.");
static_assert(
    offsetof(core::GaussianRecord, position) == 0,
    "Metal conversion output expects GaussianRecord position at float4 slot 0.");
static_assert(
    offsetof(core::GaussianRecord, pbr) == sizeof(float) * 4 * 5,
    "Metal conversion output expects GaussianRecord PBR at float4 slot 5.");
static_assert(
    core::gpu_layout::kMeshVertexAbiFloatCount == 17,
    "Metal conversion shader expects mesh vertices to remain 17 packed floats.");
static_assert(
    core::gpu_layout::kMeshVertexAbiStrideBytes == sizeof(float) * 17,
    "Metal conversion shader expects packed mesh vertex ABI stride.");
static_assert(
    core::kMeshVertexPositionOffsetBytes == sizeof(float) * 0 &&
        core::kMeshVertexNormalOffsetBytes == sizeof(float) * 3 &&
        core::kMeshVertexTangentOffsetBytes == sizeof(float) * 6 &&
        core::kMeshVertexUvOffsetBytes == sizeof(float) * 10 &&
        core::kMeshVertexNormalizedUvOffsetBytes == sizeof(float) * 12 &&
        core::kMeshVertexScaleOffsetBytes == sizeof(float) * 14,
    "Metal conversion shader mesh vertex component offsets must match GpuTypes.");

void setErrorMessage(std::string* errorMessage, std::string message)
{
    if (errorMessage != nullptr) {
        *errorMessage = std::move(message);
    } else {
        NSLog(@"%s", message.c_str());
    }
}

void clearErrorMessage(std::string* errorMessage)
{
    if (errorMessage != nullptr) {
        errorMessage->clear();
    }
}

bool failEncode(std::string* errorMessage, std::string message)
{
    setErrorMessage(errorMessage, std::move(message));
    return false;
}

bool failEncodeAfterEnding(
    id<MTLComputeCommandEncoder> encoder,
    std::string* errorMessage,
    std::string message)
{
    [encoder endEncoding];
    return failEncode(errorMessage, std::move(message));
}

std::string rangeDiagnosticPrefix(std::size_t meshIndex, uint32_t rangeIndex)
{
    return "Metal mesh conversion failed for mesh " + std::to_string(meshIndex) +
        ", draw range " + std::to_string(rangeIndex) + ": ";
}

std::size_t ceilDivide(std::size_t value, std::size_t divisor)
{
    return divisor == 0 ? 0 : (value + divisor - 1) / divisor;
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
    MetalRenderStateCache& renderStateCache,
    std::string* errorMessage)
{
    if (m_impl == nullptr) {
        setErrorMessage(errorMessage, "Failed to initialize mesh conversion pass: implementation storage is missing.");
        return false;
    }

    MetalComputePipelineDesc pipelineDesc;
    pipelineDesc.label = "Mesh Vertex Conversion Pipeline";
    pipelineDesc.function = std::string(bindings::functions::kMeshVertexConversionKernel);
    std::string pipelineError;
    m_impl->computePipelineState = pipelineCache.computePipeline(shaderLibrary, pipelineDesc, &pipelineError);
    if (m_impl->computePipelineState == nullptr) {
        std::string message =
            "Failed to initialize mesh conversion compute pipeline '" + pipelineDesc.function + "'";
        if (!pipelineDesc.label.empty()) {
            message += " (" + pipelineDesc.label + ")";
        }
        if (!pipelineError.empty()) {
            message += ": " + pipelineError;
        } else {
            message += ": pipeline cache returned no diagnostic.";
        }
        setErrorMessage(errorMessage, std::move(message));
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
    if (m_impl->samplerState == nullptr) {
        setErrorMessage(errorMessage, "Failed to initialize mesh conversion texture sampler.");
        return false;
    }

    if (errorMessage != nullptr) {
        errorMessage->clear();
    }
    return true;
}

bool MetalConversionPass::isReady() const
{
    return m_impl != nullptr && m_impl->computePipelineState != nullptr && m_impl->samplerState != nullptr;
}

bool MetalConversionPass::encode(
    void* commandBuffer,
    const MetalSceneResources& sceneResources,
    MetalGaussianBuffer& gaussianBuffer,
    uint32_t samplesPerTriangle,
    std::string* errorMessage) const
{
    if (m_impl == nullptr) {
        return failEncode(errorMessage, "Metal mesh conversion pass implementation storage is missing.");
    }
    if (!isReady()) {
        return failEncode(errorMessage, "Metal mesh conversion pass is not initialized.");
    }
    if (commandBuffer == nullptr) {
        return failEncode(errorMessage, "Metal mesh conversion received a null command buffer.");
    }
    if (sceneResources.meshCount() == 0 || sceneResources.totalVertexCount() == 0 ||
        sceneResources.totalDrawRangeCount() == 0) {
        return failEncode(errorMessage, "Metal mesh conversion received empty scene resources.");
    }
    if (!sceneResources.isValid()) {
        return failEncode(errorMessage, "Metal mesh conversion received invalid scene resources.");
    }
    if (gaussianBuffer.capacity() == 0) {
        return failEncode(errorMessage, "Metal mesh conversion received a zero-capacity gaussian output buffer.");
    }
    if (!gaussianBuffer.isValid()) {
        return failEncode(errorMessage, "Metal mesh conversion received an invalid gaussian output buffer.");
    }

    const uint32_t sampleCount = normalizedSamplesPerTriangle(samplesPerTriangle);
    const std::size_t gaussianCapacity = gaussianBuffer.capacity();
    if (!core::gaussianCountFitsBuffer(gaussianCapacity)) {
        return failEncode(
            errorMessage,
            "Metal mesh conversion gaussian capacity exceeds the 32-bit shader counter limit.");
    }

    const std::size_t gaussianBufferBytes = core::gaussianBufferByteSize(gaussianCapacity);
    if (gaussianBufferBytes == 0 || gaussianBuffer.sizeBytes() < gaussianBufferBytes) {
        return failEncode(
            errorMessage,
            "Metal mesh conversion gaussian buffer is smaller than its GaussianRecord ABI capacity.");
    }

    const std::size_t plannedGaussianCapacity = sceneResources.conversionCapacity(sampleCount);
    if (plannedGaussianCapacity == 0) {
        return failEncode(errorMessage, "Metal mesh conversion planned gaussian capacity is zero.");
    }
    if (plannedGaussianCapacity > gaussianCapacity) {
        return failEncode(
            errorMessage,
            "Metal mesh conversion gaussian capacity " + std::to_string(gaussianCapacity) +
                " is below the planned conversion capacity " +
                std::to_string(plannedGaussianCapacity) + ".");
    }

    id<MTLCommandBuffer> nativeCommandBuffer = (__bridge id<MTLCommandBuffer>)commandBuffer;
    id<MTLComputePipelineState> pipelineState =
        (__bridge id<MTLComputePipelineState>)m_impl->computePipelineState;
    id<MTLSamplerState> samplerState = (__bridge id<MTLSamplerState>)m_impl->samplerState;
    id<MTLBuffer> outputBuffer = (__bridge id<MTLBuffer>)gaussianBuffer.nativeBuffer();
    id<MTLBuffer> counterBuffer = (__bridge id<MTLBuffer>)gaussianBuffer.nativeCounterBuffer();
    if (nativeCommandBuffer == nil || pipelineState == nil || samplerState == nil ||
        outputBuffer == nil || counterBuffer == nil) {
        return failEncode(errorMessage, "Metal mesh conversion could not bridge required Metal resources.");
    }

    if (outputBuffer.length < gaussianBufferBytes) {
        return failEncode(
            errorMessage,
            "Metal mesh conversion output buffer length " + std::to_string(outputBuffer.length) +
                " is below required GaussianRecord bytes " + std::to_string(gaussianBufferBytes) + ".");
    }
    if (counterBuffer.length < sizeof(uint32_t)) {
        return failEncode(errorMessage, "Metal mesh conversion counter buffer is smaller than uint32_t.");
    }

    const std::size_t computedThreadsPerGroup = computeThreadgroupSize1D((__bridge void*)pipelineState);
    const NSUInteger threadsPerGroup = static_cast<NSUInteger>(computedThreadsPerGroup);
    if (pipelineState.threadExecutionWidth == 0 || pipelineState.maxTotalThreadsPerThreadgroup == 0 ||
        computedThreadsPerGroup == 0 || threadsPerGroup > pipelineState.maxTotalThreadsPerThreadgroup) {
        return failEncode(
            errorMessage,
            "Metal mesh conversion computed an invalid threadgroup size " +
                std::to_string(computedThreadsPerGroup) + " for pipeline execution width " +
                std::to_string(pipelineState.threadExecutionWidth) + " and max threads " +
                std::to_string(pipelineState.maxTotalThreadsPerThreadgroup) + ".");
    }

    if (!gaussianBuffer.encodeResetGpuCounter(commandBuffer)) {
        return failEncode(errorMessage, "Metal mesh conversion failed to reset the gaussian counter.");
    }

    id<MTLComputeCommandEncoder> encoder = [nativeCommandBuffer computeCommandEncoder];
    if (encoder == nil) {
        return failEncode(errorMessage, "Metal mesh conversion failed to create a compute command encoder.");
    }

    encoder.label = [NSString stringWithFormat:@"Mesh2Splat Mesh Conversion %ux (%zu meshes, %zu/%zu gaussians)",
                                               sampleCount,
                                               sceneResources.meshCount(),
                                               plannedGaussianCapacity,
                                               gaussianCapacity];
    [encoder setComputePipelineState:pipelineState];
    [encoder setSamplerState:samplerState atIndex:bindings::mesh_conversion::samplers::kMaterialTextures];
    [encoder setBuffer:outputBuffer offset:0 atIndex:bindings::mesh_conversion::buffers::kGaussians];
    [encoder setBuffer:counterBuffer offset:0 atIndex:bindings::mesh_conversion::buffers::kGaussianCounter];

    for (std::size_t meshIndex = 0; meshIndex < sceneResources.meshCount(); ++meshIndex) {
        const MetalMesh* mesh = sceneResources.meshAt(meshIndex);
        if (mesh == nullptr || !mesh->isValid()) {
            return failEncodeAfterEnding(
                encoder,
                errorMessage,
                "Metal mesh conversion encountered an invalid mesh at index " + std::to_string(meshIndex) + ".");
        }

        id<MTLBuffer> vertexBuffer = (__bridge id<MTLBuffer>)mesh->vertexBuffer();
        id<MTLBuffer> materialBuffer = (__bridge id<MTLBuffer>)mesh->materialBuffer();
        if (vertexBuffer == nil || materialBuffer == nil) {
            return failEncodeAfterEnding(
                encoder,
                errorMessage,
                "Metal mesh conversion mesh " + std::to_string(meshIndex) +
                    " is missing vertex or material buffers.");
        }

        [encoder setBuffer:vertexBuffer offset:0 atIndex:bindings::mesh_conversion::buffers::kVertices];
        [encoder setBuffer:materialBuffer offset:0 atIndex:bindings::mesh_conversion::buffers::kMaterials];

        for (uint32_t rangeIndex = 0; rangeIndex < mesh->drawRangeCount(); ++rangeIndex) {
            const MetalMeshDrawRange* range = mesh->drawRange(rangeIndex);
            const std::string rangePrefix = rangeDiagnosticPrefix(meshIndex, rangeIndex);
            if (range == nullptr) {
                return failEncodeAfterEnding(
                    encoder,
                    errorMessage,
                    rangePrefix + "draw range metadata is missing.");
            }
            if (range->vertexCount == 0) {
                return failEncodeAfterEnding(
                    encoder,
                    errorMessage,
                    rangePrefix + "vertex count is zero.");
            }
            if (range->vertexCount % 3 != 0) {
                return failEncodeAfterEnding(
                    encoder,
                    errorMessage,
                    rangePrefix + "vertex count is not divisible by three.");
            }
            if (range->vertexOffset > mesh->vertexCount() ||
                range->vertexCount > mesh->vertexCount() - range->vertexOffset) {
                return failEncodeAfterEnding(
                    encoder,
                    errorMessage,
                    rangePrefix + "vertex range exceeds the mesh vertex buffer.");
            }
            if (range->materialIndex >= mesh->materialCount()) {
                return failEncodeAfterEnding(
                    encoder,
                    errorMessage,
                    rangePrefix + "material index exceeds the material buffer.");
            }

            id<MTLTexture> baseColorTexture = (__bridge id<MTLTexture>)mesh->baseColorTexture(range->materialIndex);
            id<MTLTexture> metallicRoughnessTexture =
                (__bridge id<MTLTexture>)mesh->metallicRoughnessTexture(range->materialIndex);
            id<MTLTexture> normalTexture = (__bridge id<MTLTexture>)mesh->normalTexture(range->materialIndex);
            id<MTLTexture> occlusionTexture = (__bridge id<MTLTexture>)mesh->occlusionTexture(range->materialIndex);
            id<MTLTexture> emissiveTexture = (__bridge id<MTLTexture>)mesh->emissiveTexture(range->materialIndex);
            if (baseColorTexture == nil || metallicRoughnessTexture == nil || normalTexture == nil ||
                occlusionTexture == nil || emissiveTexture == nil) {
                return failEncodeAfterEnding(
                    encoder,
                    errorMessage,
                    rangePrefix + "one or more material textures are missing.");
            }

            [encoder setTexture:baseColorTexture atIndex:bindings::material_textures::kBaseColor];
            [encoder setTexture:metallicRoughnessTexture atIndex:bindings::material_textures::kMetallicRoughness];
            [encoder setTexture:normalTexture atIndex:bindings::material_textures::kNormal];
            [encoder setTexture:occlusionTexture atIndex:bindings::material_textures::kOcclusion];
            [encoder setTexture:emissiveTexture atIndex:bindings::material_textures::kEmissive];

            const uint32_t triangleCount = range->vertexCount / 3;
            const std::size_t dispatchThreadCount =
                static_cast<std::size_t>(triangleCount) * static_cast<std::size_t>(sampleCount);
            if (dispatchThreadCount > static_cast<std::size_t>(std::numeric_limits<uint32_t>::max())) {
                return failEncodeAfterEnding(
                    encoder,
                    errorMessage,
                    rangePrefix + "dispatch thread count exceeds the shader uint thread id limit.");
            }

            MeshConversionParams params;
            params.vertexOffset = range->vertexOffset;
            params.triangleCount = triangleCount;
            params.materialIndex = range->materialIndex;
            params.maxGaussianCount = static_cast<uint32_t>(gaussianCapacity);
            params.gaussianScale = 0.22f;
            params.normalScale = 1.0f;
            params.areaSampleDensity = areaSampleDensity(*range, triangleCount, sampleCount);
            params.maxSamplesPerTriangle = sampleCount;
            if (!std::isfinite(params.gaussianScale) || params.gaussianScale <= 0.0f ||
                !std::isfinite(params.normalScale) || params.normalScale <= 0.0f ||
                !std::isfinite(params.areaSampleDensity) || params.areaSampleDensity < 0.0f) {
                return failEncodeAfterEnding(
                    encoder,
                    errorMessage,
                    rangePrefix + "conversion parameters are invalid.");
            }

            [encoder setBytes:&params length:sizeof(params) atIndex:bindings::mesh_conversion::buffers::kParams];
            const std::size_t dispatchThreadgroupCount =
                ceilDivide(dispatchThreadCount, computedThreadsPerGroup);
            if (dispatchThreadgroupCount == 0) {
                return failEncodeAfterEnding(
                    encoder,
                    errorMessage,
                    rangePrefix + "dispatch threadgroup count is zero.");
            }
            if (dispatchThreadgroupCount >
                static_cast<std::size_t>(std::numeric_limits<uint32_t>::max()) / computedThreadsPerGroup) {
                return failEncodeAfterEnding(
                    encoder,
                    errorMessage,
                    rangePrefix + "dispatch threadgroup grid exceeds the shader uint thread id limit.");
            }

            const MTLSize gridSize = MTLSizeMake(static_cast<NSUInteger>(dispatchThreadgroupCount), 1, 1);
            const MTLSize threadgroupSize = MTLSizeMake(threadsPerGroup, 1, 1);
            [encoder dispatchThreadgroups:gridSize threadsPerThreadgroup:threadgroupSize];
        }
    }

    [encoder endEncoding];
    if (!gaussianBuffer.encodeReadbackGpuCounter(commandBuffer)) {
        return failEncode(errorMessage, "Metal mesh conversion failed to encode gaussian counter readback.");
    }

    clearErrorMessage(errorMessage);
    return true;
}

} // namespace mesh2splat::metal
