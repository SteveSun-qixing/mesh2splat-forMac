#include "MetalRenderer.hpp"

#include "MetalDeviceContext.hpp"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

namespace mesh2splat::metal {

struct MetalRenderer::Impl {
    std::unique_ptr<MetalDeviceContext> deviceContext;
    uint32_t width = 0;
    uint32_t height = 0;
};

MetalRenderer::MetalRenderer(void* metalDevice)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->deviceContext = std::make_unique<MetalDeviceContext>(metalDevice);
}

MetalRenderer::~MetalRenderer() = default;

bool MetalRenderer::initialize()
{
    if (m_impl->deviceContext == nullptr) {
        return false;
    }

    return m_impl->deviceContext->initialize();
}

void MetalRenderer::resize(uint32_t width, uint32_t height)
{
    m_impl->width = width;
    m_impl->height = height;
}

void MetalRenderer::draw(void* renderPassDescriptor, void* drawable)
{
    if (m_impl->deviceContext == nullptr || !m_impl->deviceContext->isValid() ||
        renderPassDescriptor == nullptr || drawable == nullptr) {
        return;
    }

    auto* descriptor = (__bridge MTLRenderPassDescriptor*)renderPassDescriptor;
    id<CAMetalDrawable> metalDrawable = (__bridge id<CAMetalDrawable>)drawable;
    id<MTLCommandBuffer> commandBuffer =
        (__bridge id<MTLCommandBuffer>)m_impl->deviceContext->createCommandBuffer("Mesh2Splat Metal Frame");
    if (commandBuffer == nil) {
        return;
    }

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:descriptor];
    encoder.label = @"Clear Drawable";
    [encoder endEncoding];

    [commandBuffer presentDrawable:metalDrawable];
    [commandBuffer commit];
}

} // namespace mesh2splat::metal
