#include "MetalRenderer.hpp"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

namespace mesh2splat::metal {

struct MetalRenderer::Impl {
    id<MTLDevice> device = nil;
    id<MTLCommandQueue> commandQueue = nil;
    uint32_t width = 0;
    uint32_t height = 0;
};

MetalRenderer::MetalRenderer(void* metalDevice)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->device = (__bridge id<MTLDevice>)metalDevice;
}

MetalRenderer::~MetalRenderer() = default;

bool MetalRenderer::initialize()
{
    if (m_impl->device == nil) {
        return false;
    }

    m_impl->commandQueue = [m_impl->device newCommandQueue];
    m_impl->commandQueue.label = @"Mesh2Splat Metal Command Queue";
    return m_impl->commandQueue != nil;
}

void MetalRenderer::resize(uint32_t width, uint32_t height)
{
    m_impl->width = width;
    m_impl->height = height;
}

void MetalRenderer::draw(void* renderPassDescriptor, void* drawable)
{
    if (m_impl->commandQueue == nil || renderPassDescriptor == nullptr || drawable == nullptr) {
        return;
    }

    auto* descriptor = (__bridge MTLRenderPassDescriptor*)renderPassDescriptor;
    id<CAMetalDrawable> metalDrawable = (__bridge id<CAMetalDrawable>)drawable;
    id<MTLCommandBuffer> commandBuffer = [m_impl->commandQueue commandBuffer];
    commandBuffer.label = @"Mesh2Splat Metal Frame";

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:descriptor];
    encoder.label = @"Clear Drawable";
    [encoder endEncoding];

    [commandBuffer presentDrawable:metalDrawable];
    [commandBuffer commit];
}

} // namespace mesh2splat::metal
