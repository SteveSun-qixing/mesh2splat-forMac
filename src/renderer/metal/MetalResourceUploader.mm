#include "MetalResourceUploader.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>
#include <cstring>

namespace mesh2splat::metal {

MetalResourceUploader::MetalResourceUploader(void* metalDevice, void* commandQueue)
    : m_device(metalDevice)
    , m_commandQueue(commandQueue)
{
}

bool MetalResourceUploader::uploadBufferToPrivate(
    const void* data,
    std::size_t size,
    void* destinationBuffer,
    const char* label) const
{
    id<MTLDevice> device = (__bridge id<MTLDevice>)m_device;
    id<MTLCommandQueue> commandQueue = (__bridge id<MTLCommandQueue>)m_commandQueue;
    id<MTLBuffer> targetBuffer = (__bridge id<MTLBuffer>)destinationBuffer;
    if (device == nil || commandQueue == nil || targetBuffer == nil || data == nullptr || size == 0) {
        return false;
    }

    id<MTLBuffer> stagingBuffer = [device newBufferWithLength:size options:MTLResourceStorageModeShared];
    if (stagingBuffer == nil || stagingBuffer.contents == nullptr) {
        return false;
    }

    if (label != nullptr) {
        stagingBuffer.label = [NSString stringWithFormat:@"%s Upload Staging", label];
    }
    std::memcpy(stagingBuffer.contents, data, size);

    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    if (commandBuffer == nil) {
        return false;
    }

    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    if (blitEncoder == nil) {
        return false;
    }

    commandBuffer.label = @"Mesh2Splat Private Buffer Upload";
    blitEncoder.label = @"Mesh2Splat Private Buffer Upload Blit";
    [blitEncoder copyFromBuffer:stagingBuffer
                   sourceOffset:0
                       toBuffer:targetBuffer
              destinationOffset:0
                           size:size];
    [blitEncoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    return commandBuffer.status == MTLCommandBufferStatusCompleted;
}

bool MetalResourceUploader::uploadTexture2DToPrivate(
    const void* data,
    std::size_t sourceBytesPerRow,
    std::size_t copyBytesPerRow,
    std::size_t destinationBytesPerRow,
    std::size_t uploadSize,
    uint32_t width,
    uint32_t height,
    uint32_t mipLevel,
    void* destinationTexture,
    const char* label) const
{
    id<MTLDevice> device = (__bridge id<MTLDevice>)m_device;
    id<MTLCommandQueue> commandQueue = (__bridge id<MTLCommandQueue>)m_commandQueue;
    id<MTLTexture> targetTexture = (__bridge id<MTLTexture>)destinationTexture;
    if (device == nil || commandQueue == nil || targetTexture == nil || data == nullptr ||
        sourceBytesPerRow == 0 || copyBytesPerRow == 0 || destinationBytesPerRow == 0 || uploadSize == 0 ||
        width == 0 || height == 0) {
        return false;
    }

    if (copyBytesPerRow > sourceBytesPerRow || copyBytesPerRow > destinationBytesPerRow) {
        return false;
    }

    id<MTLBuffer> stagingBuffer = [device newBufferWithLength:uploadSize options:MTLResourceStorageModeShared];
    if (stagingBuffer == nil || stagingBuffer.contents == nullptr) {
        return false;
    }

    if (label != nullptr) {
        stagingBuffer.label = [NSString stringWithFormat:@"%s Upload Staging", label];
    }

    auto* destination = static_cast<std::byte*>(stagingBuffer.contents);
    const auto* source = static_cast<const std::byte*>(data);
    for (uint32_t row = 0; row < height; ++row) {
        std::memcpy(
            destination + static_cast<std::size_t>(row) * destinationBytesPerRow,
            source + static_cast<std::size_t>(row) * sourceBytesPerRow,
            copyBytesPerRow);
    }

    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    if (commandBuffer == nil) {
        return false;
    }

    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    if (blitEncoder == nil) {
        return false;
    }

    commandBuffer.label = @"Mesh2Splat Private Texture Upload";
    blitEncoder.label = @"Mesh2Splat Private Texture Upload Blit";
    [blitEncoder copyFromBuffer:stagingBuffer
                   sourceOffset:0
              sourceBytesPerRow:destinationBytesPerRow
            sourceBytesPerImage:uploadSize
                     sourceSize:MTLSizeMake(width, height, 1)
                      toTexture:targetTexture
               destinationSlice:0
               destinationLevel:mipLevel
              destinationOrigin:MTLOriginMake(0, 0, 0)];
    [blitEncoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    return commandBuffer.status == MTLCommandBufferStatusCompleted;
}

} // namespace mesh2splat::metal
