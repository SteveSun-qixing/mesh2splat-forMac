#include "MetalDeviceContext.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

namespace mesh2splat::metal {

struct MetalDeviceContext::Impl {
    id<MTLDevice> device = nil;
    id<MTLCommandQueue> commandQueue = nil;
};

MetalDeviceContext::MetalDeviceContext(void* metalDevice)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->device = (__bridge id<MTLDevice>)metalDevice;
}

MetalDeviceContext::~MetalDeviceContext() = default;

bool MetalDeviceContext::initialize()
{
    if (m_impl->device == nil) {
        return false;
    }

    m_impl->commandQueue = [m_impl->device newCommandQueue];
    m_impl->commandQueue.label = @"Mesh2Splat Metal Command Queue";
    return m_impl->commandQueue != nil;
}

bool MetalDeviceContext::isValid() const
{
    return m_impl->device != nil && m_impl->commandQueue != nil;
}

void* MetalDeviceContext::nativeDevice() const
{
    return (__bridge void*)m_impl->device;
}

void* MetalDeviceContext::nativeCommandQueue() const
{
    return (__bridge void*)m_impl->commandQueue;
}

} // namespace mesh2splat::metal
