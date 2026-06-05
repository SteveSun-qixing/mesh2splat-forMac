#include "MetalRenderTarget.hpp"

#include "MetalDeviceContext.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <utility>

namespace mesh2splat::metal {

struct MetalRenderTarget::Impl {
    MetalDeviceContext* deviceContext = nullptr;
    MetalRenderTargetDesc desc;
    std::unique_ptr<MetalTexture> colorTexture;
    std::unique_ptr<MetalTexture> depthTexture;
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
    if (m_impl->deviceContext == nullptr || desc.width == 0 || desc.height == 0 ||
        (!desc.colorEnabled && !desc.depthEnabled)) {
        return false;
    }

    m_impl->desc = desc;
    m_impl->colorTexture.reset();
    m_impl->depthTexture.reset();

    if (desc.colorEnabled) {
        m_impl->colorTexture = std::make_unique<MetalTexture>(*m_impl->deviceContext);
        const std::string label = desc.label.empty() ? "MetalRenderTarget Color" : desc.label + " Color";
        if (!m_impl->colorTexture->create2D(
                desc.width,
                desc.height,
                desc.colorFormat,
                MetalTextureUsage::ShaderRead | MetalTextureUsage::RenderTarget,
                label.c_str())) {
            m_impl->colorTexture.reset();
            return false;
        }
    }

    if (desc.depthEnabled) {
        m_impl->depthTexture = std::make_unique<MetalTexture>(*m_impl->deviceContext);
        const std::string label = desc.label.empty() ? "MetalRenderTarget Depth" : desc.label + " Depth";
        if (!m_impl->depthTexture->create2D(
                desc.width,
                desc.height,
                desc.depthFormat,
                MetalTextureUsage::ShaderRead | MetalTextureUsage::RenderTarget,
                label.c_str())) {
            m_impl->depthTexture.reset();
            return false;
        }
    }

    return true;
}

bool MetalRenderTarget::resize(uint32_t width, uint32_t height)
{
    if (width == 0 || height == 0 || m_impl->desc.width == 0 || m_impl->desc.height == 0) {
        return false;
    }

    if (m_impl->desc.width == width && m_impl->desc.height == height) {
        return true;
    }

    MetalRenderTargetDesc resizedDesc = m_impl->desc;
    resizedDesc.width = width;
    resizedDesc.height = height;
    return create(resizedDesc);
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

    return (__bridge_retained void*)descriptor;
}

void MetalRenderTarget::releaseRenderPassDescriptor(void* descriptor)
{
    if (descriptor != nullptr) {
        CFRelease(descriptor);
    }
}

} // namespace mesh2splat::metal
