#include "MetalBuffer.hpp"

#include "MetalDeviceContext.hpp"
#include "MetalResourceUploader.hpp"

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

MTLResourceOptions sharedResourceOptions(bool writeCombined)
{
    MTLResourceOptions options = MTLResourceStorageModeShared;
    if (writeCombined) {
        options |= MTLResourceCPUCacheModeWriteCombined;
    }
    return options;
}

} // namespace

struct MetalBuffer::Impl {
    id<MTLDevice> device = nil;
    id<MTLCommandQueue> commandQueue = nil;
    id<MTLBuffer> buffer = nil;
    std::size_t bufferSize = 0;
    bool cpuAccessible = false;
};

MetalBuffer::MetalBuffer(MetalDeviceContext& deviceContext)
    : m_impl(std::make_unique<Impl>())
{
    m_impl->device = (__bridge id<MTLDevice>)deviceContext.nativeDevice();
    m_impl->commandQueue = (__bridge id<MTLCommandQueue>)deviceContext.nativeCommandQueue();
}

MetalBuffer::~MetalBuffer() = default;

MetalBuffer::MetalBuffer(MetalBuffer&&) noexcept = default;

MetalBuffer& MetalBuffer::operator=(MetalBuffer&&) noexcept = default;

bool MetalBuffer::createShared(std::size_t size, const void* initialData, const char* label)
{
    if (m_impl->device == nil || size == 0) {
        return false;
    }

    const MTLResourceOptions options = sharedResourceOptions(false);
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

bool MetalBuffer::createSharedWriteCombined(std::size_t size, const void* initialData, const char* label)
{
    if (m_impl->device == nil || size == 0) {
        return false;
    }

    const MTLResourceOptions options = sharedResourceOptions(true);
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

bool MetalBuffer::createPrivateWithData(std::size_t size, const void* initialData, const char* label)
{
    if (m_impl->device == nil || m_impl->commandQueue == nil || size == 0 || initialData == nullptr) {
        return false;
    }

    MetalResourceUploadBatch uploadBatch(
        (__bridge void*)m_impl->device,
        (__bridge void*)m_impl->commandQueue,
        "Mesh2Splat Private Buffer Upload",
        "Mesh2Splat Private Buffer Upload Blit");
    if (!createPrivateWithData(size, initialData, uploadBatch, label)) {
        return false;
    }

    if (!uploadBatch.commitAndWait()) {
        m_impl->buffer = nil;
        m_impl->bufferSize = 0;
        m_impl->cpuAccessible = false;
        return false;
    }

    return true;
}

bool MetalBuffer::createPrivateWithData(
    std::size_t size,
    const void* initialData,
    MetalResourceUploadBatch& uploadBatch,
    const char* label)
{
    if (m_impl->device == nil || size == 0 || initialData == nullptr || !uploadBatch.isValid()) {
        return false;
    }

    id<MTLBuffer> privateBuffer = [m_impl->device newBufferWithLength:size options:MTLResourceStorageModePrivate];
    if (privateBuffer == nil) {
        return false;
    }

    if (label != nullptr) {
        privateBuffer.label = [NSString stringWithUTF8String:label];
    }

    if (!uploadBatch.uploadBufferToPrivate(initialData, size, (__bridge void*)privateBuffer, label)) {
        return false;
    }

    m_impl->buffer = privateBuffer;
    m_impl->bufferSize = size;
    m_impl->cpuAccessible = false;
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

bool MetalBuffer::encodeFill(void* commandBuffer, uint8_t value, std::size_t offset, std::size_t size) const
{
    id<MTLCommandBuffer> nativeCommandBuffer = (__bridge id<MTLCommandBuffer>)commandBuffer;
    if (nativeCommandBuffer == nil || m_impl->buffer == nil || offset > m_impl->bufferSize) {
        return false;
    }

    const std::size_t fillSize = size == 0 ? m_impl->bufferSize - offset : size;
    if (fillSize == 0 || fillSize > m_impl->bufferSize - offset) {
        return false;
    }

    id<MTLBlitCommandEncoder> blitEncoder = [nativeCommandBuffer blitCommandEncoder];
    if (blitEncoder == nil) {
        return false;
    }

    blitEncoder.label = @"Mesh2Splat Buffer Fill";
    [blitEncoder fillBuffer:m_impl->buffer range:NSMakeRange(offset, fillSize) value:value];
    [blitEncoder endEncoding];
    return true;
}

bool MetalBuffer::encodeCopyTo(
    void* commandBuffer,
    const MetalBuffer& destination,
    std::size_t size,
    std::size_t sourceOffset,
    std::size_t destinationOffset) const
{
    id<MTLCommandBuffer> nativeCommandBuffer = (__bridge id<MTLCommandBuffer>)commandBuffer;
    id<MTLBuffer> destinationBuffer = (__bridge id<MTLBuffer>)destination.nativeBuffer();
    if (nativeCommandBuffer == nil || m_impl->buffer == nil || destinationBuffer == nil ||
        size == 0 || sourceOffset > m_impl->bufferSize || size > m_impl->bufferSize - sourceOffset ||
        destinationOffset > destination.size() || size > destination.size() - destinationOffset) {
        return false;
    }

    id<MTLBlitCommandEncoder> blitEncoder = [nativeCommandBuffer blitCommandEncoder];
    if (blitEncoder == nil) {
        return false;
    }

    blitEncoder.label = @"Mesh2Splat Buffer Copy";
    [blitEncoder copyFromBuffer:m_impl->buffer
                   sourceOffset:sourceOffset
                       toBuffer:destinationBuffer
              destinationOffset:destinationOffset
                           size:size];
    [blitEncoder endEncoding];
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
