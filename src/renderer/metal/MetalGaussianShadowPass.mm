#include "MetalGaussianShadowPass.hpp"

#include "MetalFrameUniformBuffer.hpp"
#include "MetalGaussianBuffer.hpp"
#include "MetalPipelineCache.hpp"
#include "MetalRenderStateCache.hpp"
#include "MetalShaderLibrary.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstring>
#include <iterator>
#include <limits>
#include <sstream>
#include <string>
#include <utility>

namespace mesh2splat::metal {
namespace {

constexpr uint32_t kDefaultShadowMapSize = 1024;
constexpr uint32_t kMinimumShadowMapSize = 128;
constexpr uint32_t kMaximumShadowMapSize = 4096;
constexpr uint32_t kShadowFaceCount = 6;
constexpr uint32_t kShadowFrameSlots = 3;
constexpr float kPi = 3.14159265358979323846f;

struct Vec3 {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
};

float radians(float degrees)
{
    return degrees * kPi / 180.0f;
}

Vec3 add(Vec3 lhs, Vec3 rhs)
{
    return Vec3{lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z};
}

Vec3 subtract(Vec3 lhs, Vec3 rhs)
{
    return Vec3{lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z};
}

float dot(Vec3 lhs, Vec3 rhs)
{
    return lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z;
}

float length(Vec3 value)
{
    return std::sqrt(dot(value, value));
}

Vec3 scale(Vec3 value, float multiplier)
{
    return Vec3{value.x * multiplier, value.y * multiplier, value.z * multiplier};
}

Vec3 cross(Vec3 lhs, Vec3 rhs)
{
    return Vec3{
        lhs.y * rhs.z - lhs.z * rhs.y,
        lhs.z * rhs.x - lhs.x * rhs.z,
        lhs.x * rhs.y - lhs.y * rhs.x,
    };
}

Vec3 normalize(Vec3 value)
{
    const float vectorLength = length(value);
    if (vectorLength <= 1.0e-6f) {
        return Vec3{};
    }
    return scale(value, 1.0f / vectorLength);
}

core::Matrix4 multiply(const core::Matrix4& lhs, const core::Matrix4& rhs)
{
    core::Matrix4 result{};
    std::fill(std::begin(result.values), std::end(result.values), 0.0f);

    for (int column = 0; column < 4; ++column) {
        for (int row = 0; row < 4; ++row) {
            float value = 0.0f;
            for (int index = 0; index < 4; ++index) {
                value += lhs.values[index * 4 + row] * rhs.values[column * 4 + index];
            }
            result.values[column * 4 + row] = value;
        }
    }

    return result;
}

core::Matrix4 lookAt(Vec3 eye, Vec3 center, Vec3 worldUp)
{
    const Vec3 forward = normalize(subtract(center, eye));
    const Vec3 right = normalize(cross(forward, worldUp));
    const Vec3 up = cross(right, forward);

    core::Matrix4 result{};
    result.values[0] = right.x;
    result.values[1] = up.x;
    result.values[2] = -forward.x;
    result.values[4] = right.y;
    result.values[5] = up.y;
    result.values[6] = -forward.y;
    result.values[8] = right.z;
    result.values[9] = up.z;
    result.values[10] = -forward.z;
    result.values[12] = -dot(right, eye);
    result.values[13] = -dot(up, eye);
    result.values[14] = dot(forward, eye);
    return result;
}

core::Matrix4 perspectiveDepthZeroToOne(float verticalFovDegrees, float aspectRatio, float nearPlane, float farPlane)
{
    core::Matrix4 result{};
    std::fill(std::begin(result.values), std::end(result.values), 0.0f);

    const float resolvedNear = std::max(nearPlane, 1.0e-4f);
    const float resolvedFar = std::max(farPlane, resolvedNear + 1.0e-3f);
    const float yScale = 1.0f / std::tan(radians(verticalFovDegrees) * 0.5f);
    const float xScale = yScale / std::max(aspectRatio, 1.0e-4f);
    result.values[0] = xScale;
    result.values[5] = yScale;
    result.values[10] = resolvedFar / (resolvedNear - resolvedFar);
    result.values[11] = -1.0f;
    result.values[14] = -(resolvedFar * resolvedNear) / (resolvedFar - resolvedNear);
    return result;
}

uint32_t normalizeShadowMapSize(uint32_t requestedSize)
{
    if (requestedSize == 0) {
        requestedSize = kDefaultShadowMapSize;
    }
    return std::clamp(requestedSize, kMinimumShadowMapSize, kMaximumShadowMapSize);
}

Vec3 lightPositionFromFrame(const core::FrameUniforms& frame)
{
    return Vec3{
        frame.lightPositionIntensity[0],
        frame.lightPositionIntensity[1],
        frame.lightPositionIntensity[2],
    };
}

std::array<core::FrameUniforms, kShadowFaceCount> makeShadowFaceUniforms(
    const core::FrameUniforms& source,
    uint32_t shadowMapSize)
{
    const Vec3 lightPosition = lightPositionFromFrame(source);
    const std::array<Vec3, kShadowFaceCount> directions = {
        Vec3{1.0f, 0.0f, 0.0f},
        Vec3{-1.0f, 0.0f, 0.0f},
        Vec3{0.0f, 1.0f, 0.0f},
        Vec3{0.0f, -1.0f, 0.0f},
        Vec3{0.0f, 0.0f, 1.0f},
        Vec3{0.0f, 0.0f, -1.0f},
    };
    const std::array<Vec3, kShadowFaceCount> upVectors = {
        Vec3{0.0f, -1.0f, 0.0f},
        Vec3{0.0f, -1.0f, 0.0f},
        Vec3{0.0f, 0.0f, 1.0f},
        Vec3{0.0f, 0.0f, -1.0f},
        Vec3{0.0f, -1.0f, 0.0f},
        Vec3{0.0f, -1.0f, 0.0f},
    };

    const float nearPlane = std::max(source.clippingPlanes[0], 1.0e-4f);
    const float farPlane = std::max(source.clippingPlanes[1], nearPlane + 1.0f);
    const core::Matrix4 projection = perspectiveDepthZeroToOne(90.0f, 1.0f, nearPlane, farPlane);
    const float shadowMapSizeFloat = static_cast<float>(std::max<uint32_t>(shadowMapSize, 1));

    std::array<core::FrameUniforms, kShadowFaceCount> uniforms;
    for (uint32_t face = 0; face < kShadowFaceCount; ++face) {
        core::FrameUniforms faceUniforms = source;
        const core::Matrix4 view = lookAt(
            lightPosition,
            add(lightPosition, directions[face]),
            upVectors[face]);
        faceUniforms.viewMatrix = view;
        faceUniforms.projectionMatrix = projection;
        faceUniforms.modelViewProjectionMatrix = multiply(projection, multiply(view, source.modelMatrix));
        faceUniforms.cameraPosition[0] = lightPosition.x;
        faceUniforms.cameraPosition[1] = lightPosition.y;
        faceUniforms.cameraPosition[2] = lightPosition.z;
        faceUniforms.cameraPosition[3] = 1.0f;
        faceUniforms.hfovFocal[0] = 90.0f;
        faceUniforms.hfovFocal[1] = 90.0f;
        faceUniforms.hfovFocal[2] = std::fabs(projection.values[0]) * shadowMapSizeFloat * 0.5f;
        faceUniforms.hfovFocal[3] = std::fabs(projection.values[5]) * shadowMapSizeFloat * 0.5f;
        faceUniforms.viewport[0] = shadowMapSizeFloat;
        faceUniforms.viewport[1] = shadowMapSizeFloat;
        faceUniforms.viewport[2] = 1.0f / shadowMapSizeFloat;
        faceUniforms.viewport[3] = 1.0f / shadowMapSizeFloat;
        faceUniforms.clippingPlanes[0] = nearPlane;
        faceUniforms.clippingPlanes[1] = farPlane;
        faceUniforms.frameIndex = face;
        uniforms[face] = faceUniforms;
    }
    return uniforms;
}

std::string nsStringToUtf8(NSString* value)
{
    if (value == nil || value.UTF8String == nullptr) {
        return {};
    }
    return std::string(value.UTF8String);
}

void setOutput(std::string* output, const std::string& value)
{
    if (output != nullptr) {
        *output = value;
    }
}

std::size_t addBytes(std::size_t lhs, std::size_t rhs)
{
    if (rhs > std::numeric_limits<std::size_t>::max() - lhs) {
        return std::numeric_limits<std::size_t>::max();
    }
    return lhs + rhs;
}

} // namespace

struct MetalGaussianShadowPass::Impl {
    MetalDeviceContext* deviceContext = nullptr;
    std::unique_ptr<MetalTexture> shadowDistanceTexture;
    std::unique_ptr<MetalTexture> shadowDepthTexture;
    std::unique_ptr<MetalFrameUniformBuffer> faceUniformBuffer;
    void* pipelineState = nullptr;
    void* depthStencilState = nullptr;
    uint32_t shadowMapSize = 0;
    MetalGaussianShadowPassDiagnostics lastDiagnostics;
    std::string lastDiagnostic = "MetalGaussianShadowPass is not initialized.";

    bool ensureShadowMap(uint32_t requestedSize)
    {
        const uint32_t nextSize = normalizeShadowMapSize(requestedSize);
        if (shadowDistanceTexture != nullptr &&
            shadowDepthTexture != nullptr &&
            shadowDistanceTexture->isValid() &&
            shadowDepthTexture->isValid() &&
            shadowMapSize == nextSize) {
            return true;
        }

        auto nextDistance = std::make_unique<MetalTexture>(*deviceContext);
        if (!nextDistance->createCube(
                nextSize,
                MetalTextureFormat::R32Float,
                MetalTextureUsage::ShaderRead | MetalTextureUsage::RenderTarget,
                "Mesh2Splat Gaussian Shadow Distance Cube")) {
            lastDiagnostic = nextDistance->lastErrorMessage().empty()
                ? "Failed to allocate Metal gaussian shadow distance cubemap."
                : nextDistance->lastErrorMessage();
            return false;
        }

        auto nextDepth = std::make_unique<MetalTexture>(*deviceContext);
        if (!nextDepth->createCube(
                nextSize,
                MetalTextureFormat::Depth32Float,
                MetalTextureUsage::RenderTarget,
                "Mesh2Splat Gaussian Shadow Depth Cube")) {
            lastDiagnostic = nextDepth->lastErrorMessage().empty()
                ? "Failed to allocate Metal gaussian shadow depth cubemap."
                : nextDepth->lastErrorMessage();
            return false;
        }

        shadowDistanceTexture = std::move(nextDistance);
        shadowDepthTexture = std::move(nextDepth);
        shadowMapSize = nextSize;
        lastDiagnostic = "Metal gaussian shadow cubemaps ready: " + std::to_string(shadowMapSize) + "x" +
            std::to_string(shadowMapSize) + "x6.";
        return true;
    }

    std::size_t sizeBytes() const
    {
        std::size_t total = 0;
        total = addBytes(total, shadowDistanceTexture == nullptr ? 0 : shadowDistanceTexture->sizeBytes());
        total = addBytes(total, shadowDepthTexture == nullptr ? 0 : shadowDepthTexture->sizeBytes());
        total = addBytes(total, faceUniformBuffer == nullptr ? 0 : faceUniformBuffer->sizeBytes());
        return total;
    }

    void updateDiagnostics(uint32_t gaussianCount = 0, bool encoded = false)
    {
        lastDiagnostics.ready = pipelineState != nullptr && depthStencilState != nullptr &&
            faceUniformBuffer != nullptr && faceUniformBuffer->isValid();
        lastDiagnostics.shadowMapReady =
            shadowDistanceTexture != nullptr && shadowDistanceTexture->isValid() &&
            shadowDepthTexture != nullptr && shadowDepthTexture->isValid();
        lastDiagnostics.encoded = encoded;
        lastDiagnostics.shadowMapSize = shadowMapSize;
        lastDiagnostics.gaussianCount = gaussianCount;
        lastDiagnostics.shadowDistanceBytes =
            shadowDistanceTexture == nullptr ? 0 : shadowDistanceTexture->sizeBytes();
        lastDiagnostics.shadowDepthBytes =
            shadowDepthTexture == nullptr ? 0 : shadowDepthTexture->sizeBytes();
        lastDiagnostics.uniformBytes =
            faceUniformBuffer == nullptr ? 0 : faceUniformBuffer->sizeBytes();
        lastDiagnostics.totalBytes = sizeBytes();
        lastDiagnostics.lastMessage = lastDiagnostic;
    }
};

MetalGaussianShadowPass::MetalGaussianShadowPass(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->deviceContext = &deviceContext;
}

MetalGaussianShadowPass::~MetalGaussianShadowPass() = default;

MetalGaussianShadowPass::MetalGaussianShadowPass(MetalGaussianShadowPass&&) noexcept = default;

MetalGaussianShadowPass& MetalGaussianShadowPass::operator=(MetalGaussianShadowPass&&) noexcept = default;

bool MetalGaussianShadowPass::initialize(
    MetalShaderLibrary& shaderLibrary,
    MetalPipelineCache& pipelineCache,
    MetalRenderStateCache& renderStateCache,
    uint32_t shadowMapSize,
    std::string* errorMessage)
{
    if (m_impl->deviceContext == nullptr) {
        m_impl->lastDiagnostic = "Cannot initialize Metal gaussian shadow pass: device context is null.";
        setOutput(errorMessage, m_impl->lastDiagnostic);
        return false;
    }

    MetalRenderPipelineDesc pipelineDesc = MetalPipelineCache::gaussianShadowPipelineDesc(
        MetalTextureFormat::R32Float,
        MetalTextureFormat::Depth32Float);
    std::string pipelineError;
    m_impl->pipelineState = pipelineCache.renderPipeline(shaderLibrary, pipelineDesc, &pipelineError);
    if (m_impl->pipelineState == nullptr) {
        m_impl->lastDiagnostic = pipelineError.empty()
            ? "Failed to create Metal gaussian shadow pipeline."
            : pipelineError;
        setOutput(errorMessage, m_impl->lastDiagnostic);
        return false;
    }

    MetalDepthStencilDesc depthDesc;
    depthDesc.label = "Gaussian Shadow Depth";
    depthDesc.depthTestEnabled = true;
    depthDesc.depthWriteEnabled = true;
    depthDesc.depthCompareFunction = MetalCompareFunction::LessEqual;
    std::string depthError;
    m_impl->depthStencilState = renderStateCache.depthStencilState(depthDesc, &depthError);
    if (m_impl->depthStencilState == nullptr) {
        m_impl->lastDiagnostic = depthError.empty()
            ? "Failed to create Metal gaussian shadow depth state."
            : depthError;
        setOutput(errorMessage, m_impl->lastDiagnostic);
        return false;
    }

    m_impl->faceUniformBuffer = std::make_unique<MetalFrameUniformBuffer>(
        *m_impl->deviceContext,
        kShadowFrameSlots * kShadowFaceCount);
    if (!m_impl->faceUniformBuffer->initialize("Mesh2Splat Shadow Face Uniforms")) {
        m_impl->lastDiagnostic = m_impl->faceUniformBuffer->lastDiagnostic();
        setOutput(errorMessage, m_impl->lastDiagnostic);
        return false;
    }

    if (!m_impl->ensureShadowMap(shadowMapSize)) {
        setOutput(errorMessage, m_impl->lastDiagnostic);
        return false;
    }

    m_impl->lastDiagnostic = "Metal gaussian shadow pass initialized.";
    m_impl->updateDiagnostics();
    setOutput(errorMessage, std::string{});
    return true;
}

bool MetalGaussianShadowPass::isReady() const
{
    return m_impl->pipelineState != nullptr &&
        m_impl->depthStencilState != nullptr &&
        m_impl->faceUniformBuffer != nullptr &&
        m_impl->faceUniformBuffer->isValid() &&
        m_impl->shadowDistanceTexture != nullptr &&
        m_impl->shadowDistanceTexture->isValid() &&
        m_impl->shadowDepthTexture != nullptr &&
        m_impl->shadowDepthTexture->isValid();
}

bool MetalGaussianShadowPass::resizeShadowMap(uint32_t shadowMapSize)
{
    const bool resized = m_impl->ensureShadowMap(shadowMapSize);
    m_impl->updateDiagnostics();
    return resized;
}

uint32_t MetalGaussianShadowPass::shadowMapSize() const
{
    return m_impl->shadowMapSize;
}

std::size_t MetalGaussianShadowPass::sizeBytes() const
{
    return m_impl->sizeBytes();
}

void* MetalGaussianShadowPass::shadowDistanceTexture() const
{
    return m_impl->shadowDistanceTexture == nullptr ? nullptr : m_impl->shadowDistanceTexture->nativeTexture();
}

const std::string& MetalGaussianShadowPass::lastDiagnostic() const
{
    return m_impl->lastDiagnostic;
}

MetalGaussianShadowPassDiagnostics MetalGaussianShadowPass::diagnostics() const
{
    m_impl->updateDiagnostics(m_impl->lastDiagnostics.gaussianCount, m_impl->lastDiagnostics.encoded);
    return m_impl->lastDiagnostics;
}

bool MetalGaussianShadowPass::encode(
    void* commandBuffer,
    const MetalGaussianBuffer& gaussianBuffer,
    const core::FrameUniforms& frameUniforms,
    uint32_t frameResourceIndex)
{
    id<MTLCommandBuffer> nativeCommandBuffer = (__bridge id<MTLCommandBuffer>)commandBuffer;
    id<MTLRenderPipelineState> pipelineState = (__bridge id<MTLRenderPipelineState>)m_impl->pipelineState;
    id<MTLDepthStencilState> depthStencilState = (__bridge id<MTLDepthStencilState>)m_impl->depthStencilState;
    id<MTLTexture> shadowDistanceTexture =
        (__bridge id<MTLTexture>)(m_impl->shadowDistanceTexture == nullptr ? nullptr : m_impl->shadowDistanceTexture->nativeTexture());
    id<MTLTexture> shadowDepthTexture =
        (__bridge id<MTLTexture>)(m_impl->shadowDepthTexture == nullptr ? nullptr : m_impl->shadowDepthTexture->nativeTexture());
    id<MTLBuffer> gaussianNativeBuffer = (__bridge id<MTLBuffer>)gaussianBuffer.nativeBuffer();

    const uint32_t gaussianCount = gaussianBuffer.count();
    if (nativeCommandBuffer == nil || pipelineState == nil || depthStencilState == nil ||
        shadowDistanceTexture == nil || shadowDepthTexture == nil ||
        gaussianNativeBuffer == nil || !gaussianBuffer.isValid() || gaussianCount == 0 ||
        m_impl->faceUniformBuffer == nullptr || !m_impl->faceUniformBuffer->isValid()) {
        m_impl->lastDiagnostic = "Metal gaussian shadow pass skipped: resources are not ready.";
        m_impl->updateDiagnostics(gaussianCount, false);
        return false;
    }

    const uint32_t shadowMapSize = std::max<uint32_t>(m_impl->shadowMapSize, 1);
    const auto faceUniforms = makeShadowFaceUniforms(frameUniforms, shadowMapSize);
    const uint32_t frameSlot = frameResourceIndex % kShadowFrameSlots;
    for (uint32_t face = 0; face < kShadowFaceCount; ++face) {
        const uint32_t uniformIndex = frameSlot * kShadowFaceCount + face;
        std::ostringstream label;
        label << "Mesh2Splat Shadow Face " << face << " Frame " << frameSlot;
        if (!m_impl->faceUniformBuffer->update(uniformIndex, faceUniforms[face], label.str().c_str())) {
            m_impl->lastDiagnostic = m_impl->faceUniformBuffer->lastDiagnostic();
            m_impl->updateDiagnostics(gaussianCount, false);
            return false;
        }
    }

    for (uint32_t face = 0; face < kShadowFaceCount; ++face) {
        MTLRenderPassDescriptor* descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
        MTLRenderPassColorAttachmentDescriptor* colorAttachment = descriptor.colorAttachments[0];
        colorAttachment.texture = shadowDistanceTexture;
        colorAttachment.level = 0;
        colorAttachment.slice = face;
        colorAttachment.loadAction = MTLLoadActionClear;
        colorAttachment.storeAction = MTLStoreActionStore;
        colorAttachment.clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0);

        MTLRenderPassDepthAttachmentDescriptor* depthAttachment = descriptor.depthAttachment;
        depthAttachment.texture = shadowDepthTexture;
        depthAttachment.level = 0;
        depthAttachment.slice = face;
        depthAttachment.loadAction = MTLLoadActionClear;
        depthAttachment.storeAction = MTLStoreActionDontCare;
        depthAttachment.clearDepth = 1.0;

        id<MTLRenderCommandEncoder> encoder = [nativeCommandBuffer renderCommandEncoderWithDescriptor:descriptor];
        if (encoder == nil) {
            m_impl->lastDiagnostic = "Metal gaussian shadow pass failed: render command encoder is nil.";
            m_impl->updateDiagnostics(gaussianCount, false);
            return false;
        }

        encoder.label = [NSString stringWithFormat:@"Mesh2Splat Gaussian Shadow Face %u", face];
        [encoder setViewport:MTLViewport{
            0.0,
            0.0,
            static_cast<double>(shadowMapSize),
            static_cast<double>(shadowMapSize),
            0.0,
            1.0}];
        [encoder setCullMode:MTLCullModeNone];
        [encoder setRenderPipelineState:pipelineState];
        [encoder setDepthStencilState:depthStencilState];
        [encoder setVertexBuffer:gaussianNativeBuffer offset:0 atIndex:0];

        const uint32_t uniformIndex = frameSlot * kShadowFaceCount + face;
        id<MTLBuffer> uniformBuffer = (__bridge id<MTLBuffer>)m_impl->faceUniformBuffer->buffer(uniformIndex);
        if (uniformBuffer == nil) {
            [encoder endEncoding];
            m_impl->lastDiagnostic = "Metal gaussian shadow pass failed: face uniform buffer is nil.";
            m_impl->updateDiagnostics(gaussianCount, false);
            return false;
        }
        [encoder setVertexBuffer:uniformBuffer offset:0 atIndex:1];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                    vertexStart:0
                    vertexCount:6
                  instanceCount:gaussianCount];
        [encoder endEncoding];
    }

    m_impl->lastDiagnostic = "Metal gaussian shadow pass encoded " +
        std::to_string(gaussianCount) + " gaussians into a " +
        std::to_string(shadowMapSize) + "px cubemap.";
    m_impl->updateDiagnostics(gaussianCount, true);
    return true;
}

} // namespace mesh2splat::metal
