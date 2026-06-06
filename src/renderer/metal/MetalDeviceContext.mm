#include "MetalDeviceContext.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

namespace mesh2splat::metal {
namespace {

std::string nsStringValue(NSString* value)
{
    if (value == nil || value.UTF8String == nullptr) {
        return std::string{};
    }

    return std::string(value.UTF8String);
}

MetalDeviceContext::ArgumentBufferTier argumentBufferTierFromMetal(MTLArgumentBuffersTier tier)
{
    switch (tier) {
    case MTLArgumentBuffersTier1:
        return MetalDeviceContext::ArgumentBufferTier::Tier1;
    case MTLArgumentBuffersTier2:
        return MetalDeviceContext::ArgumentBufferTier::Tier2;
    default:
        return MetalDeviceContext::ArgumentBufferTier::Unsupported;
    }
}

MetalDeviceContext::Capabilities collectCapabilities(id<MTLDevice> device)
{
    MetalDeviceContext::Capabilities capabilities;
    if (device == nil) {
        return capabilities;
    }

    capabilities.deviceName = nsStringValue(device.name);
    capabilities.isLowPower = device.isLowPower;
    capabilities.isHeadless = device.isHeadless;

    if (@available(macOS 10.13, *)) {
        capabilities.isRemovable = device.isRemovable;
        capabilities.argumentBufferTier = argumentBufferTierFromMetal(device.argumentBuffersSupport);
        capabilities.supportsArgumentBuffers =
            capabilities.argumentBufferTier != MetalDeviceContext::ArgumentBufferTier::Unsupported;
    }

    if (@available(macOS 10.14, *)) {
        capabilities.maxBufferLength = static_cast<std::size_t>(device.maxBufferLength);
    }

    if (@available(macOS 10.15, *)) {
        capabilities.hasUnifiedMemory = device.hasUnifiedMemory;
    }

    return capabilities;
}

} // namespace

struct MetalDeviceContext::Impl {
    id<MTLDevice> device = nil;
    id<MTLCommandQueue> commandQueue = nil;
    Capabilities capabilities;
};

MetalDeviceContext::MetalDeviceContext(void* metalDevice)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->device = (__bridge id<MTLDevice>)metalDevice;
    m_impl->capabilities = collectCapabilities(m_impl->device);
}

MetalDeviceContext::~MetalDeviceContext() = default;

bool MetalDeviceContext::initialize()
{
    if (m_impl->device == nil) {
        m_impl->capabilities = collectCapabilities(nil);
        return false;
    }

    m_impl->capabilities = collectCapabilities(m_impl->device);
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

const MetalDeviceContext::Capabilities& MetalDeviceContext::capabilities() const
{
    return m_impl->capabilities;
}

const std::string& MetalDeviceContext::deviceName() const
{
    return m_impl->capabilities.deviceName;
}

std::size_t MetalDeviceContext::maxBufferLength() const
{
    return m_impl->capabilities.maxBufferLength;
}

MetalDeviceContext::ArgumentBufferTier MetalDeviceContext::argumentBufferTier() const
{
    return m_impl->capabilities.argumentBufferTier;
}

bool MetalDeviceContext::supportsArgumentBuffers() const
{
    return m_impl->capabilities.supportsArgumentBuffers;
}

bool MetalDeviceContext::hasUnifiedMemory() const
{
    return m_impl->capabilities.hasUnifiedMemory;
}

bool MetalDeviceContext::isLowPower() const
{
    return m_impl->capabilities.isLowPower;
}

bool MetalDeviceContext::isRemovable() const
{
    return m_impl->capabilities.isRemovable;
}

bool MetalDeviceContext::isHeadless() const
{
    return m_impl->capabilities.isHeadless;
}

} // namespace mesh2splat::metal
