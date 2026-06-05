#include "MetalRenderer.hpp"

#include "MetalDeviceContext.hpp"
#include "MetalFrameResources.hpp"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

namespace mesh2splat::metal {

struct MetalRenderer::Impl {
    std::unique_ptr<MetalDeviceContext> deviceContext;
    MetalFrameResources frameResources;
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

    m_impl->frameResources.beginFrame();

    auto* descriptor = (__bridge MTLRenderPassDescriptor*)renderPassDescriptor;
    id<CAMetalDrawable> metalDrawable = (__bridge id<CAMetalDrawable>)drawable;
    id<MTLCommandQueue> commandQueue =
        (__bridge id<MTLCommandQueue>)m_impl->deviceContext->nativeCommandQueue();
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    if (commandBuffer == nil) {
        return;
    }
    commandBuffer.label = @"Mesh2Splat Metal Frame";

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:descriptor];
    encoder.label = @"Clear Drawable";
    [encoder endEncoding];

    [commandBuffer presentDrawable:metalDrawable];
    [commandBuffer commit];
}

} // namespace mesh2splat::metal
