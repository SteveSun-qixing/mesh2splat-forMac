#include "MetalRenderer.hpp"

#include "core/FrameData.hpp"
#include "MetalDeviceContext.hpp"
#include "MetalFrameUniformBuffer.hpp"
#include "MetalFrameResources.hpp"
#include "MetalRenderStateCache.hpp"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

namespace mesh2splat::metal {

struct MetalRenderer::Impl {
    std::unique_ptr<MetalDeviceContext> deviceContext;
    MetalFrameResources frameResources;
    std::unique_ptr<MetalFrameUniformBuffer> frameUniformBuffer;
    std::unique_ptr<MetalRenderStateCache> renderStateCache;
    core::FrameUniforms frameUniforms;
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

    if (!m_impl->deviceContext->initialize()) {
        return false;
    }

    m_impl->frameUniformBuffer = std::make_unique<MetalFrameUniformBuffer>(*m_impl->deviceContext);
    if (!m_impl->frameUniformBuffer->initialize("Mesh2Splat Frame Uniforms")) {
        return false;
    }

    m_impl->renderStateCache = std::make_unique<MetalRenderStateCache>(*m_impl->deviceContext);
    m_impl->frameUniforms = core::makeDefaultFrameUniforms(m_impl->width, m_impl->height);
    return true;
}

void MetalRenderer::resize(uint32_t width, uint32_t height)
{
    m_impl->width = width;
    m_impl->height = height;
    m_impl->frameUniforms.viewport[0] = static_cast<float>(width);
    m_impl->frameUniforms.viewport[1] = static_cast<float>(height);
    m_impl->frameUniforms.viewport[2] = width == 0 ? 1.0f : 1.0f / static_cast<float>(width);
    m_impl->frameUniforms.viewport[3] = height == 0 ? 1.0f : 1.0f / static_cast<float>(height);
}

void MetalRenderer::draw(void* renderPassDescriptor, void* drawable)
{
    if (m_impl->deviceContext == nullptr || !m_impl->deviceContext->isValid() ||
        renderPassDescriptor == nullptr || drawable == nullptr) {
        return;
    }

    m_impl->frameResources.beginFrame();
    m_impl->frameUniforms.frameIndex = m_impl->frameResources.currentFrameIndex();
    if (m_impl->frameUniformBuffer != nullptr) {
        m_impl->frameUniformBuffer->update(
            m_impl->frameResources.currentFrameIndex(),
            m_impl->frameUniforms);
    }

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
