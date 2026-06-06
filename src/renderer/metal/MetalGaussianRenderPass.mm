#include "MetalGaussianRenderPass.hpp"

#include "MetalBindings.hpp"
#include "MetalDeviceContext.hpp"
#include "MetalGaussianBuffer.hpp"
#include "MetalGaussianSortBuffer.hpp"
#include "MetalPipelineCache.hpp"
#include "MetalRenderStateCache.hpp"
#include "MetalShaderLibrary.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <string>
#include <utility>

namespace mesh2splat::metal {
namespace {

constexpr const char* kGaussianRenderDebugLabel = "Mesh2Splat Gaussian Preview Render";
constexpr const char* kGaussianBlendModeName = "PremultipliedAlpha";
constexpr const char* kGaussianAlphaBlendDescription =
    "premultiplied-alpha: rgb=(one, one-minus-source-alpha, add), alpha=(one, one-minus-source-alpha, add)";
constexpr const char* kGaussianAdditiveBlendDescription =
    "additive reference: rgb=(one, one, add), alpha=(one, one, add)";

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

} // namespace

struct MetalGaussianRenderPass::Impl {
    id<MTLDevice> device = nil;
    void* renderPipelineState = nullptr;
    void* depthStencilState = nullptr;
    void* samplerState = nullptr;
    id<MTLBuffer> identityIndexBuffer = nil;
    std::size_t identityIndexCapacity = 0;
    MetalTextureFormat colorFormat = MetalTextureFormat::BGRA8Unorm;
    MetalTextureFormat depthFormat = MetalTextureFormat::Depth32Float;
    std::string debugLabel = kGaussianRenderDebugLabel;
    mutable std::string lastDiagnostic;
    mutable MetalGaussianRenderPassDiagnostics lastEncodeDiagnostics;

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

    void beginEncodeDiagnostics(
        const MetalGaussianBuffer& gaussianBuffer,
        const MetalGaussianSortBuffer* sortBuffer,
        bool ready) const
    {
        lastEncodeDiagnostics = {};
        lastEncodeDiagnostics.ready = ready;
        lastEncodeDiagnostics.gaussianBufferValid = gaussianBuffer.isValid();
        lastEncodeDiagnostics.sortBufferValid = sortBuffer != nullptr && sortBuffer->isValid();
        lastEncodeDiagnostics.depthTestEnabled = true;
        lastEncodeDiagnostics.depthWriteEnabled = false;
        lastEncodeDiagnostics.gaussianCapacity = gaussianBuffer.capacity();
        lastEncodeDiagnostics.gaussianCount = gaussianBuffer.count();
        lastEncodeDiagnostics.sortCapacity = sortBuffer == nullptr ? 0 : sortBuffer->capacity();
        lastEncodeDiagnostics.sortCount = sortBuffer == nullptr ? 0 : sortBuffer->count();
        lastEncodeDiagnostics.gaussianResourceBytes = gaussianBuffer.totalSizeBytes();
        lastEncodeDiagnostics.sortResourceBytes =
            sortBuffer == nullptr ? 0 : sortBuffer->resourceStats().totalBytes;
        lastEncodeDiagnostics.identityIndexCapacity = identityIndexCapacity;
        lastEncodeDiagnostics.identityIndexBytes = identityIndexCapacity * sizeof(uint32_t);
        lastEncodeDiagnostics.colorFormat = textureFormatName(colorFormat);
        lastEncodeDiagnostics.depthFormat = textureFormatName(depthFormat);
        lastEncodeDiagnostics.blendMode = kGaussianBlendModeName;
        lastEncodeDiagnostics.alphaBlendDescription = kGaussianAlphaBlendDescription;
        lastEncodeDiagnostics.additiveBlendDescription = kGaussianAdditiveBlendDescription;
        lastEncodeDiagnostics.debugLabel = debugLabel;
    }

    bool ensureIdentityIndexCapacity(uint32_t count, std::string* diagnostic) const
    {
        if (count == 0) {
            return true;
        }
        if (identityIndexCapacity >= count && identityIndexBuffer != nil) {
            return true;
        }
        if (device == nil) {
            setErrorMessage(diagnostic, "Metal gaussian render pass cannot create identity indices: device is nil.");
            return false;
        }

        const std::size_t grownCapacity =
            identityIndexCapacity > static_cast<std::size_t>(std::numeric_limits<uint32_t>::max()) / 2
                ? static_cast<std::size_t>(std::numeric_limits<uint32_t>::max())
                : identityIndexCapacity * 2;
        const std::size_t newCapacity =
            std::max<std::size_t>(count, std::max<std::size_t>(grownCapacity, 256));
        if (newCapacity > (std::numeric_limits<NSUInteger>::max() / sizeof(uint32_t))) {
            setErrorMessage(diagnostic, "Metal gaussian render pass cannot create identity indices: size overflow.");
            return false;
        }

        const MTLResourceOptions options = MTLResourceStorageModeShared | MTLResourceCPUCacheModeWriteCombined;
        id<MTLBuffer> newBuffer = [device newBufferWithLength:newCapacity * sizeof(uint32_t) options:options];
        if (newBuffer == nil) {
            setErrorMessage(diagnostic, "Metal gaussian render pass cannot create identity index buffer.");
            return false;
        }
        if (newBuffer.contents == nullptr) {
            setErrorMessage(diagnostic, "Metal gaussian render pass cannot fill identity index buffer.");
            return false;
        }

        uint32_t* indices = static_cast<uint32_t*>(newBuffer.contents);
        for (std::size_t index = 0; index < newCapacity; ++index) {
            indices[index] = static_cast<uint32_t>(index);
        }

        newBuffer.label = @"Mesh2Splat Gaussian Identity Indices";
        const_cast<Impl*>(this)->identityIndexBuffer = newBuffer;
        const_cast<Impl*>(this)->identityIndexCapacity = newCapacity;
        if (diagnostic != nullptr) {
            diagnostic->clear();
        }
        return true;
    }
};

MetalGaussianRenderPass::MetalGaussianRenderPass(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->device = (__bridge id<MTLDevice>)deviceContext.nativeDevice();
}

MetalGaussianRenderPass::~MetalGaussianRenderPass() = default;

MetalGaussianRenderPass::MetalGaussianRenderPass(MetalGaussianRenderPass&&) noexcept = default;

MetalGaussianRenderPass& MetalGaussianRenderPass::operator=(MetalGaussianRenderPass&&) noexcept = default;

bool MetalGaussianRenderPass::initialize(
    MetalShaderLibrary& shaderLibrary,
    MetalPipelineCache& pipelineCache,
    MetalRenderStateCache& renderStateCache,
    MetalTextureFormat colorFormat,
    MetalTextureFormat depthFormat,
    std::string* errorMessage)
{
    if (m_impl == nullptr) {
        setErrorMessage(errorMessage, "Failed to initialize gaussian render pass: implementation storage is missing.");
        return false;
    }

    m_impl->resetPipelineState();
    m_impl->colorFormat = colorFormat;
    m_impl->depthFormat = depthFormat;
    m_impl->lastEncodeDiagnostics = {};
    m_impl->lastEncodeDiagnostics.debugLabel = m_impl->debugLabel;

    MetalRenderPipelineDesc pipelineDesc;
    pipelineDesc.label = "Gaussian Preview Pipeline";
    pipelineDesc.vertexFunction = std::string(bindings::functions::kGaussianPreviewVertex);
    pipelineDesc.fragmentFunction = std::string(bindings::functions::kGaussianPreviewFragment);
    pipelineDesc.colorFormat = colorFormat;
    pipelineDesc.depthFormat = depthFormat;
    pipelineDesc.depthEnabled = true;
    pipelineDesc.blendMode = MetalBlendMode::PremultipliedAlpha;
    pipelineDesc.variantKey = std::string(textureFormatName(colorFormat)) + "/" + textureFormatName(depthFormat) +
        "/blend=" + kGaussianBlendModeName;

    std::string pipelineError;
    m_impl->renderPipelineState = pipelineCache.renderPipeline(shaderLibrary, pipelineDesc, &pipelineError);
    if (m_impl->renderPipelineState == nullptr) {
        std::string message =
            "Failed to initialize gaussian render pipeline '" + pipelineDesc.vertexFunction + "/" +
            pipelineDesc.fragmentFunction + "' for colorFormat=" + textureFormatName(colorFormat) +
            ", depthFormat=" + textureFormatName(depthFormat) + ", blendMode=" + kGaussianBlendModeName;
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
    depthDesc.label = "Gaussian Preview Depth";
    depthDesc.depthTestEnabled = true;
    depthDesc.depthWriteEnabled = false;
    depthDesc.depthCompareFunction = MetalCompareFunction::LessEqual;
    std::string depthDiagnostic;
    m_impl->depthStencilState = renderStateCache.depthStencilState(depthDesc, &depthDiagnostic);
    if (m_impl->depthStencilState == nullptr) {
        std::string message = "Failed to initialize gaussian render depth state.";
        if (!depthDiagnostic.empty()) {
            message += " " + depthDiagnostic;
        }
        m_impl->recordDiagnostic(message);
        setErrorMessage(errorMessage, std::move(message));
        return false;
    }

    MetalSamplerDesc samplerDesc;
    samplerDesc.label = "Gaussian Preview Sampler";
    samplerDesc.minFilter = MetalSamplerFilter::Linear;
    samplerDesc.magFilter = MetalSamplerFilter::Linear;
    samplerDesc.mipFilter = MetalSamplerFilter::Linear;
    samplerDesc.addressU = MetalSamplerAddressMode::ClampToEdge;
    samplerDesc.addressV = MetalSamplerAddressMode::ClampToEdge;
    samplerDesc.addressW = MetalSamplerAddressMode::ClampToEdge;
    std::string samplerDiagnostic;
    m_impl->samplerState = renderStateCache.samplerState(samplerDesc, &samplerDiagnostic);
    if (m_impl->samplerState == nullptr) {
        std::string message = "Failed to initialize gaussian render sampler state.";
        if (!samplerDiagnostic.empty()) {
            message += " " + samplerDiagnostic;
        }
        m_impl->recordDiagnostic(message);
        setErrorMessage(errorMessage, std::move(message));
        return false;
    }

    m_impl->recordDiagnostic(std::string{}, false);
    clearErrorMessage(errorMessage);
    return true;
}

bool MetalGaussianRenderPass::isReady() const
{
    return m_impl != nullptr &&
        m_impl->renderPipelineState != nullptr && m_impl->depthStencilState != nullptr &&
        m_impl->samplerState != nullptr;
}

const std::string& MetalGaussianRenderPass::lastDiagnostic() const
{
    static const std::string emptyDiagnostic;
    if (m_impl == nullptr) {
        return emptyDiagnostic;
    }

    return m_impl->lastDiagnostic;
}

MetalGaussianRenderPassDiagnostics MetalGaussianRenderPass::lastEncodeDiagnostics() const
{
    if (m_impl == nullptr) {
        return {};
    }

    return m_impl->lastEncodeDiagnostics;
}

void MetalGaussianRenderPass::encode(
    void* renderCommandEncoder,
    const MetalGaussianBuffer& gaussianBuffer,
    void* frameUniformBuffer) const
{
    encodeImpl(renderCommandEncoder, gaussianBuffer, nullptr, frameUniformBuffer);
}

void MetalGaussianRenderPass::encode(
    void* renderCommandEncoder,
    const MetalGaussianBuffer& gaussianBuffer,
    const MetalGaussianSortBuffer& sortBuffer,
    void* frameUniformBuffer) const
{
    encodeImpl(renderCommandEncoder, gaussianBuffer, &sortBuffer, frameUniformBuffer);
}

void MetalGaussianRenderPass::encodeImpl(
    void* renderCommandEncoder,
    const MetalGaussianBuffer& gaussianBuffer,
    const MetalGaussianSortBuffer* sortBuffer,
    void* frameUniformBuffer) const
{
    if (m_impl == nullptr) {
        return;
    }

    const bool ready = isReady();
    m_impl->beginEncodeDiagnostics(gaussianBuffer, sortBuffer, ready);
    if (!ready) {
        m_impl->recordDiagnostic("Metal gaussian render pass skipped: pass is not ready.");
        return;
    }
    if (renderCommandEncoder == nullptr) {
        m_impl->recordDiagnostic("Metal gaussian render pass skipped: render encoder is null.");
        return;
    }
    if (frameUniformBuffer == nullptr) {
        m_impl->recordDiagnostic("Metal gaussian render pass skipped: frame uniform buffer is null.");
        return;
    }
    if (!gaussianBuffer.isValid()) {
        std::string diagnostic = "Metal gaussian render pass skipped: gaussian buffer is invalid.";
        if (!gaussianBuffer.lastErrorMessage().empty()) {
            diagnostic += " " + gaussianBuffer.lastErrorMessage();
        }
        m_impl->recordDiagnostic(diagnostic);
        return;
    }
    if (gaussianBuffer.count() == 0) {
        m_impl->recordDiagnostic(std::string{}, false);
        return;
    }
    if (static_cast<std::size_t>(gaussianBuffer.count()) > gaussianBuffer.capacity()) {
        m_impl->recordDiagnostic("Metal gaussian render pass skipped: gaussian count exceeds buffer capacity.");
        return;
    }

    uint32_t instanceCount = gaussianBuffer.count();
    id<MTLBuffer> indexBuffer = nil;
    if (sortBuffer != nullptr &&
        sortBuffer->isValid() &&
        sortBuffer->count() == gaussianBuffer.count() &&
        static_cast<std::size_t>(sortBuffer->count()) <= sortBuffer->capacity()) {
        indexBuffer = (__bridge id<MTLBuffer>)sortBuffer->nativeIndexBuffer();
        m_impl->lastEncodeDiagnostics.usedSortedIndices = true;
        m_impl->lastEncodeDiagnostics.indexSource = "sorted";
    } else {
        if (sortBuffer == nullptr) {
            m_impl->lastEncodeDiagnostics.indexFallbackReason = "sort buffer unavailable";
        } else if (!sortBuffer->isValid()) {
            m_impl->lastEncodeDiagnostics.indexFallbackReason = "sort buffer invalid";
        } else if (sortBuffer->count() != gaussianBuffer.count()) {
            m_impl->lastEncodeDiagnostics.indexFallbackReason = "gaussian/sort counts out of sync";
        } else {
            m_impl->lastEncodeDiagnostics.indexFallbackReason = "sort count exceeds sort capacity";
        }

        std::string identityDiagnostic;
        if (!m_impl->ensureIdentityIndexCapacity(instanceCount, &identityDiagnostic)) {
            m_impl->recordDiagnostic(identityDiagnostic.empty()
                    ? "Metal gaussian render pass skipped: identity index buffer is unavailable."
                    : identityDiagnostic);
            return;
        }
        indexBuffer = m_impl->identityIndexBuffer;
        m_impl->lastEncodeDiagnostics.usedIdentityIndices = true;
        m_impl->lastEncodeDiagnostics.indexSource = "identity";
        m_impl->lastEncodeDiagnostics.identityIndexCapacity = m_impl->identityIndexCapacity;
        m_impl->lastEncodeDiagnostics.identityIndexBytes = m_impl->identityIndexCapacity * sizeof(uint32_t);
    }
    m_impl->lastEncodeDiagnostics.instanceCount = instanceCount;

    id<MTLRenderCommandEncoder> encoder = (__bridge id<MTLRenderCommandEncoder>)renderCommandEncoder;
    id<MTLRenderPipelineState> pipelineState = (__bridge id<MTLRenderPipelineState>)m_impl->renderPipelineState;
    id<MTLDepthStencilState> depthStencilState = (__bridge id<MTLDepthStencilState>)m_impl->depthStencilState;
    id<MTLSamplerState> samplerState = (__bridge id<MTLSamplerState>)m_impl->samplerState;
    id<MTLBuffer> gaussianBufferHandle = (__bridge id<MTLBuffer>)gaussianBuffer.nativeBuffer();
    id<MTLBuffer> frameBuffer = (__bridge id<MTLBuffer>)frameUniformBuffer;
    if (encoder == nil || pipelineState == nil || depthStencilState == nil || samplerState == nil ||
        gaussianBufferHandle == nil || indexBuffer == nil || frameBuffer == nil) {
        m_impl->recordDiagnostic("Metal gaussian render pass skipped: native Metal resources are unavailable.");
        return;
    }

    m_impl->recordDiagnostic(std::string{});

    if (encoder.label == nil) {
        encoder.label = @"Mesh2Splat Drawable Render";
    }
    [encoder pushDebugGroup:stringFromUtf8(m_impl->debugLabel.c_str())];
    [encoder setRenderPipelineState:pipelineState];
    [encoder setDepthStencilState:depthStencilState];
    [encoder setVertexBuffer:gaussianBufferHandle
                       offset:0
                      atIndex:bindings::gaussian_preview::vertex_buffers::kGaussians];
    [encoder setVertexBuffer:frameBuffer
                       offset:0
                      atIndex:bindings::gaussian_preview::vertex_buffers::kFrameUniforms];
    [encoder setVertexBuffer:indexBuffer
                       offset:0
                      atIndex:bindings::gaussian_preview::vertex_buffers::kGaussianIndices];
    [encoder setFragmentBuffer:frameBuffer
                         offset:0
                        atIndex:bindings::gaussian_preview::fragment_buffers::kFrameUniforms];
    [encoder setFragmentSamplerState:samplerState atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:6
              instanceCount:instanceCount];
    [encoder popDebugGroup];
}

} // namespace mesh2splat::metal
