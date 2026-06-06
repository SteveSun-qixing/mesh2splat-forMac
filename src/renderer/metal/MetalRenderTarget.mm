#include "MetalRenderTarget.hpp"

#include "MetalDeviceContext.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <limits>
#include <utility>

namespace mesh2splat::metal {

namespace {

const char* defaultLabelForRole(MetalRenderTargetRole role)
{
    switch (role) {
    case MetalRenderTargetRole::Main:
        return "Main Render Target";
    case MetalRenderTargetRole::Depth:
        return "Depth Render Target";
    case MetalRenderTargetRole::Offscreen:
        return "Offscreen Render Target";
    case MetalRenderTargetRole::Unknown:
        return "MetalRenderTarget";
    }

    return "MetalRenderTarget";
}

std::string debugLabelForDesc(const MetalRenderTargetDesc& desc)
{
    return desc.label.empty() ? defaultLabelForRole(desc.role) : desc.label;
}

NSString* stringFromUtf8(const std::string& value)
{
    return value.empty() ? nil : [NSString stringWithUTF8String:value.c_str()];
}

bool allocationDescMatches(const MetalRenderTargetDesc& lhs, const MetalRenderTargetDesc& rhs)
{
    return lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.colorEnabled == rhs.colorEnabled &&
        lhs.depthEnabled == rhs.depthEnabled &&
        lhs.colorFormat == rhs.colorFormat &&
        lhs.depthFormat == rhs.depthFormat;
}

bool addSize(std::size_t lhs, std::size_t rhs, std::size_t& result)
{
    if (lhs > std::numeric_limits<std::size_t>::max() - rhs) {
        result = 0;
        return false;
    }

    result = lhs + rhs;
    return true;
}

} // namespace

struct MetalRenderTarget::Impl {
    MetalDeviceContext* deviceContext = nullptr;
    MetalRenderTargetDesc desc;
    std::unique_ptr<MetalTexture> colorTexture;
    std::unique_ptr<MetalTexture> depthTexture;
    std::string debugLabel = "MetalRenderTarget";
    std::string colorDebugLabel = "MetalRenderTarget Color";
    std::string depthDebugLabel = "MetalRenderTarget Depth";
    std::string lastErrorMessage;

    void updateDebugLabels()
    {
        debugLabel = debugLabelForDesc(desc);
        colorDebugLabel = debugLabel + " Color";
        depthDebugLabel = debugLabel + " Depth";
    }

    void applyDebugLabels() const
    {
        if (colorTexture != nullptr) {
            id<MTLTexture> texture = (__bridge id<MTLTexture>)colorTexture->nativeTexture();
            if (texture != nil) {
                texture.label = stringFromUtf8(colorDebugLabel);
            }
        }

        if (depthTexture != nullptr) {
            id<MTLTexture> texture = (__bridge id<MTLTexture>)depthTexture->nativeTexture();
            if (texture != nil) {
                texture.label = stringFromUtf8(depthDebugLabel);
            }
        }
    }

    void setError(std::string message)
    {
        lastErrorMessage = std::move(message);
    }

    void clearError()
    {
        lastErrorMessage.clear();
    }
};

MetalRenderTarget::MetalRenderTarget(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->deviceContext = &deviceContext;
}

MetalRenderTarget::~MetalRenderTarget() = default;

MetalRenderTarget::MetalRenderTarget(MetalRenderTarget&&) noexcept = default;

MetalRenderTarget& MetalRenderTarget::operator=(MetalRenderTarget&&) noexcept = default;

bool MetalRenderTarget::create(const MetalRenderTargetDesc& desc)
{
    if (m_impl->deviceContext == nullptr) {
        m_impl->setError("Metal render target creation failed: Metal device context is unavailable.");
        return false;
    }

    if (desc.width == 0 || desc.height == 0) {
        m_impl->setError("Metal render target creation failed: width and height must be non-zero.");
        return false;
    }

    if (!desc.colorEnabled && !desc.depthEnabled) {
        m_impl->setError("Metal render target creation failed: at least one attachment must be enabled.");
        return false;
    }

    MetalRenderTargetDesc nextDesc = desc;
    const std::string debugLabel = debugLabelForDesc(nextDesc);
    const std::string colorDebugLabel = debugLabel + " Color";
    const std::string depthDebugLabel = debugLabel + " Depth";
    std::unique_ptr<MetalTexture> colorTexture;
    std::unique_ptr<MetalTexture> depthTexture;

    if (desc.colorEnabled) {
        colorTexture = std::make_unique<MetalTexture>(*m_impl->deviceContext);
        if (!colorTexture->create2D(
                desc.width,
                desc.height,
                desc.colorFormat,
                MetalTextureUsage::ShaderRead | MetalTextureUsage::RenderTarget,
                colorDebugLabel.c_str())) {
            m_impl->setError("Metal render target creation failed: color texture allocation failed.");
            return false;
        }
    }

    if (desc.depthEnabled) {
        depthTexture = std::make_unique<MetalTexture>(*m_impl->deviceContext);
        if (!depthTexture->create2D(
                desc.width,
                desc.height,
                desc.depthFormat,
                MetalTextureUsage::ShaderRead | MetalTextureUsage::RenderTarget,
                depthDebugLabel.c_str())) {
            m_impl->setError("Metal render target creation failed: depth texture allocation failed.");
            return false;
        }
    }

    m_impl->desc = nextDesc;
    m_impl->colorTexture = std::move(colorTexture);
    m_impl->depthTexture = std::move(depthTexture);
    m_impl->updateDebugLabels();
    m_impl->applyDebugLabels();
    m_impl->clearError();
    return true;
}

bool MetalRenderTarget::resize(uint32_t width, uint32_t height)
{
    return resize(resizeDescriptor(width, height));
}

bool MetalRenderTarget::resize(const MetalRenderTargetDesc& desc)
{
    if (m_impl->desc.width == 0 || m_impl->desc.height == 0) {
        m_impl->setError("Metal render target resize failed: target has not been created yet.");
        return false;
    }

    if (desc.width == 0 || desc.height == 0) {
        m_impl->setError("Metal render target resize failed: width and height must be non-zero.");
        return false;
    }

    if (!desc.colorEnabled && !desc.depthEnabled) {
        m_impl->setError("Metal render target resize failed: at least one attachment must be enabled.");
        return false;
    }

    if (!allocationDescMatches(m_impl->desc, desc)) {
        return create(desc);
    }

    m_impl->desc = desc;
    m_impl->updateDebugLabels();
    m_impl->applyDebugLabels();
    m_impl->clearError();
    return true;
}

MetalRenderTargetDesc MetalRenderTarget::resizeDescriptor(uint32_t width, uint32_t height) const
{
    MetalRenderTargetDesc desc = m_impl->desc;
    desc.width = width;
    desc.height = height;
    return desc;
}

bool MetalRenderTarget::isValid() const
{
    const bool hasColor = !m_impl->desc.colorEnabled ||
        (m_impl->colorTexture != nullptr && m_impl->colorTexture->isValid());
    const bool hasDepth = !m_impl->desc.depthEnabled ||
        (m_impl->depthTexture != nullptr && m_impl->depthTexture->isValid());
    return (m_impl->desc.colorEnabled || m_impl->desc.depthEnabled) && hasColor && hasDepth;
}

uint32_t MetalRenderTarget::width() const
{
    return m_impl->desc.width;
}

uint32_t MetalRenderTarget::height() const
{
    return m_impl->desc.height;
}

MetalRenderTargetSize MetalRenderTarget::size() const
{
    return { m_impl->desc.width, m_impl->desc.height };
}

const MetalRenderTargetDesc& MetalRenderTarget::descriptor() const
{
    return m_impl->desc;
}

MetalRenderTargetRole MetalRenderTarget::role() const
{
    return m_impl->desc.role;
}

bool MetalRenderTarget::colorEnabled() const
{
    return m_impl->desc.colorEnabled;
}

bool MetalRenderTarget::depthEnabled() const
{
    return m_impl->desc.depthEnabled;
}

MetalTextureFormat MetalRenderTarget::colorFormat() const
{
    return m_impl->desc.colorFormat;
}

MetalTextureFormat MetalRenderTarget::depthFormat() const
{
    return m_impl->desc.depthFormat;
}

std::size_t MetalRenderTarget::colorSizeBytes() const
{
    return m_impl->colorTexture == nullptr ? 0 : m_impl->colorTexture->sizeBytes();
}

std::size_t MetalRenderTarget::depthSizeBytes() const
{
    return m_impl->depthTexture == nullptr ? 0 : m_impl->depthTexture->sizeBytes();
}

std::size_t MetalRenderTarget::sizeBytes() const
{
    std::size_t total = 0;
    if (!addSize(colorSizeBytes(), depthSizeBytes(), total)) {
        return 0;
    }

    return total;
}

MetalClearColor MetalRenderTarget::clearColorValue() const
{
    return m_impl->desc.clearColor;
}

double MetalRenderTarget::clearDepthValue() const
{
    return m_impl->desc.clearDepth;
}

const std::string& MetalRenderTarget::debugLabel() const
{
    return m_impl->debugLabel;
}

std::string MetalRenderTarget::colorDebugLabel() const
{
    return m_impl->colorDebugLabel;
}

std::string MetalRenderTarget::depthDebugLabel() const
{
    return m_impl->depthDebugLabel;
}

const std::string& MetalRenderTarget::lastErrorMessage() const
{
    return m_impl->lastErrorMessage;
}

MetalRenderTargetDiagnostics MetalRenderTarget::diagnostics() const
{
    MetalRenderTargetDiagnostics diagnostics;
    diagnostics.valid = isValid();
    diagnostics.role = m_impl->desc.role;
    diagnostics.size = size();
    diagnostics.colorEnabled = m_impl->desc.colorEnabled;
    diagnostics.depthEnabled = m_impl->desc.depthEnabled;
    diagnostics.colorFormat = m_impl->desc.colorFormat;
    diagnostics.depthFormat = m_impl->desc.depthFormat;
    diagnostics.colorSizeBytes = colorSizeBytes();
    diagnostics.depthSizeBytes = depthSizeBytes();
    diagnostics.totalSizeBytes = sizeBytes();
    diagnostics.clearColor = m_impl->desc.clearColor;
    diagnostics.clearDepth = m_impl->desc.clearDepth;
    diagnostics.debugLabel = m_impl->debugLabel;
    diagnostics.colorDebugLabel = m_impl->colorDebugLabel;
    diagnostics.depthDebugLabel = m_impl->depthDebugLabel;
    diagnostics.lastErrorMessage = m_impl->lastErrorMessage;
    return diagnostics;
}

void* MetalRenderTarget::colorTexture() const
{
    return m_impl->colorTexture == nullptr ? nullptr : m_impl->colorTexture->nativeTexture();
}

void* MetalRenderTarget::depthTexture() const
{
    return m_impl->depthTexture == nullptr ? nullptr : m_impl->depthTexture->nativeTexture();
}

void* MetalRenderTarget::createRenderPassDescriptor(bool clearColor, bool clearDepth) const
{
    if (!isValid()) {
        m_impl->setError("Metal render pass descriptor creation failed: render target is not valid.");
        return nullptr;
    }

    MTLRenderPassDescriptor* descriptor = [MTLRenderPassDescriptor renderPassDescriptor];

    if (m_impl->desc.colorEnabled && m_impl->colorTexture != nullptr) {
        MTLRenderPassColorAttachmentDescriptor* colorAttachment = descriptor.colorAttachments[0];
        colorAttachment.texture = (__bridge id<MTLTexture>)m_impl->colorTexture->nativeTexture();
        colorAttachment.loadAction = clearColor ? MTLLoadActionClear : MTLLoadActionLoad;
        colorAttachment.storeAction = MTLStoreActionStore;
        const MetalClearColor& color = m_impl->desc.clearColor;
        colorAttachment.clearColor = MTLClearColorMake(color.red, color.green, color.blue, color.alpha);
    }

    if (m_impl->desc.depthEnabled && m_impl->depthTexture != nullptr) {
        MTLRenderPassDepthAttachmentDescriptor* depthAttachment = descriptor.depthAttachment;
        depthAttachment.texture = (__bridge id<MTLTexture>)m_impl->depthTexture->nativeTexture();
        depthAttachment.loadAction = clearDepth ? MTLLoadActionClear : MTLLoadActionLoad;
        depthAttachment.storeAction = MTLStoreActionStore;
        depthAttachment.clearDepth = m_impl->desc.clearDepth;
    }

    m_impl->clearError();
    return (__bridge_retained void*)descriptor;
}

void MetalRenderTarget::releaseRenderPassDescriptor(void* descriptor)
{
    if (descriptor != nullptr) {
        CFRelease(descriptor);
    }
}

const char* MetalRenderTarget::roleName(MetalRenderTargetRole role)
{
    switch (role) {
    case MetalRenderTargetRole::Unknown:
        return "Unknown";
    case MetalRenderTargetRole::Main:
        return "Main";
    case MetalRenderTargetRole::Depth:
        return "Depth";
    case MetalRenderTargetRole::Offscreen:
        return "Offscreen";
    }

    return "Unknown";
}

} // namespace mesh2splat::metal
