#include "MetalBuffer.hpp"

#include "MetalDeviceContext.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>
#include <cstring>
#include <utility>

namespace mesh2splat::metal {
namespace {

bool storageModeIsCpuAccessible(MTLResourceOptions options)
{
    const MTLResourceOptions storageMode = options & MTLResourceStorageModeMask;
    return storageMode == MTLResourceStorageModeShared;
}

} // namespace

struct MetalBuffer::Impl {
    id<MTLDevice> device = nil;
    id<MTLBuffer> buffer = nil;
    std::size_t bufferSize = 0;
    bool cpuAccessible = false;
};

MetalBuffer::MetalBuffer(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->device = (__bridge id<MTLDevice>)deviceContext.nativeDevice();
}

MetalBuffer::~MetalBuffer() = default;

MetalBuffer::MetalBuffer(MetalBuffer&&) noexcept = default;

MetalBuffer& MetalBuffer::operator=(MetalBuffer&&) noexcept = default;

bool MetalBuffer::createShared(std::size_t size, const void* initialData, const char* label)
{
    if (m_impl->device == nil || size == 0) {
        return false;
    }

    constexpr MTLResourceOptions options = MTLResourceStorageModeShared;
    m_impl->buffer = [m_impl->device newBufferWithLength:size options:options];
    if (m_impl->buffer == nil) {
        m_impl->bufferSize = 0;
        m_impl->cpuAccessible = false;
        return false;
    }

    m_impl->bufferSize = size;
    m_impl->cpuAccessible = storageModeIsCpuAccessible(options);
    if (label != nullptr) {
        m_impl->buffer.label = [NSString stringWithUTF8String:label];
    }

    if (initialData != nullptr) {
        std::memcpy(m_impl->buffer.contents, initialData, size);
    }

    return true;
}

bool MetalBuffer::createPrivate(std::size_t size, const char* label)
{
    if (m_impl->device == nil || size == 0) {
        return false;
    }

    constexpr MTLResourceOptions options = MTLResourceStorageModePrivate;
    m_impl->buffer = [m_impl->device newBufferWithLength:size options:options];
    if (m_impl->buffer == nil) {
        m_impl->bufferSize = 0;
        m_impl->cpuAccessible = false;
        return false;
    }

    m_impl->bufferSize = size;
    m_impl->cpuAccessible = storageModeIsCpuAccessible(options);
    if (label != nullptr) {
        m_impl->buffer.label = [NSString stringWithUTF8String:label];
    }

    return true;
}

bool MetalBuffer::update(const void* data, std::size_t size, std::size_t offset)
{
    if (m_impl->buffer == nil || !m_impl->cpuAccessible || m_impl->buffer.contents == nullptr ||
        data == nullptr || offset > m_impl->bufferSize ||
        size > m_impl->bufferSize - offset) {
        return false;
    }

    auto* bytes = static_cast<std::byte*>(m_impl->buffer.contents);
    std::memcpy(bytes + offset, data, size);
    return true;
}

bool MetalBuffer::read(void* destination, std::size_t size, std::size_t offset) const
{
    if (m_impl->buffer == nil || !m_impl->cpuAccessible || m_impl->buffer.contents == nullptr ||
        destination == nullptr || offset > m_impl->bufferSize ||
        size > m_impl->bufferSize - offset) {
        return false;
    }

    const auto* bytes = static_cast<const std::byte*>(m_impl->buffer.contents);
    std::memcpy(destination, bytes + offset, size);
    return true;
}

bool MetalBuffer::isValid() const
{
    return m_impl->buffer != nil;
}

bool MetalBuffer::isCpuAccessible() const
{
    return m_impl->buffer != nil && m_impl->cpuAccessible;
}

std::size_t MetalBuffer::size() const
{
    return m_impl->bufferSize;
}

void* MetalBuffer::nativeBuffer() const
{
    return (__bridge void*)m_impl->buffer;
}

} // namespace mesh2splat::metal
