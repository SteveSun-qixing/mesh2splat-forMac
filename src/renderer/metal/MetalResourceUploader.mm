#include "MetalResourceUploader.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>
#include <cstring>

namespace mesh2splat::metal {
namespace {

NSString* labelString(const char* label)
{
    return label == nullptr ? nil : [NSString stringWithUTF8String:label];
}

NSString* uploadStagingLabel(const char* label)
{
    NSString* baseLabel = labelString(label);
    return baseLabel == nil ? nil : [baseLabel stringByAppendingString:@" Upload Staging"];
}

} // namespace

struct MetalResourceUploadBatch::Impl {
    id<MTLDevice> device = nil;
    id<MTLCommandBuffer> commandBuffer = nil;
    id<MTLBlitCommandEncoder> blitEncoder = nil;
    NSMutableArray<id<MTLBuffer>>* stagingBuffers = nil;
    bool committed = false;
};

MetalResourceUploadBatch::MetalResourceUploadBatch(
    void* metalDevice,
    void* commandQueue,
    const char* commandLabel,
    const char* blitLabel)
    : m_impl(std::make_unique<Impl>())
{
    id<MTLDevice> device = (__bridge id<MTLDevice>)metalDevice;
    id<MTLCommandQueue> nativeCommandQueue = (__bridge id<MTLCommandQueue>)commandQueue;
    if (device == nil || nativeCommandQueue == nil) {
        return;
    }

    id<MTLCommandBuffer> commandBuffer = [nativeCommandQueue commandBuffer];
    if (commandBuffer == nil) {
        return;
    }

    NSString* nativeCommandLabel = labelString(commandLabel);
    if (nativeCommandLabel != nil) {
        commandBuffer.label = nativeCommandLabel;
    }

    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    if (blitEncoder == nil) {
        return;
    }

    NSString* nativeBlitLabel = labelString(blitLabel);
    if (nativeBlitLabel != nil) {
        blitEncoder.label = nativeBlitLabel;
    }

    m_impl->device = device;
    m_impl->commandBuffer = commandBuffer;
    m_impl->blitEncoder = blitEncoder;
    m_impl->stagingBuffers = [NSMutableArray array];
}

MetalResourceUploadBatch::~MetalResourceUploadBatch()
{
    if (m_impl->blitEncoder != nil && !m_impl->committed) {
        [m_impl->blitEncoder endEncoding];
        m_impl->blitEncoder = nil;
    }
}

bool MetalResourceUploadBatch::isValid() const
{
    return m_impl->device != nil &&
        m_impl->commandBuffer != nil &&
        m_impl->blitEncoder != nil &&
        m_impl->stagingBuffers != nil &&
        !m_impl->committed;
}

bool MetalResourceUploadBatch::uploadBufferToPrivate(
    const void* data,
    std::size_t size,
    void* destinationBuffer,
    const char* label)
{
    id<MTLBuffer> targetBuffer = (__bridge id<MTLBuffer>)destinationBuffer;
    if (!isValid() || targetBuffer == nil || data == nullptr || size == 0) {
        return false;
    }

    id<MTLBuffer> stagingBuffer = [m_impl->device newBufferWithLength:size options:MTLResourceStorageModeShared];
    if (stagingBuffer == nil || stagingBuffer.contents == nullptr) {
        return false;
    }

    NSString* stagingLabel = uploadStagingLabel(label);
    if (stagingLabel != nil) {
        stagingBuffer.label = stagingLabel;
    }
    std::memcpy(stagingBuffer.contents, data, size);
    [m_impl->stagingBuffers addObject:stagingBuffer];

    [m_impl->blitEncoder copyFromBuffer:stagingBuffer
                           sourceOffset:0
                               toBuffer:targetBuffer
                      destinationOffset:0
                                   size:size];
    return true;
}

bool MetalResourceUploadBatch::uploadTexture2DToPrivate(
    const void* data,
    std::size_t sourceBytesPerRow,
    std::size_t copyBytesPerRow,
    std::size_t destinationBytesPerRow,
    std::size_t uploadSize,
    uint32_t width,
    uint32_t height,
    uint32_t mipLevel,
    void* destinationTexture,
    const char* label)
{
    id<MTLTexture> targetTexture = (__bridge id<MTLTexture>)destinationTexture;
    if (!isValid() || targetTexture == nil || data == nullptr ||
        sourceBytesPerRow == 0 || copyBytesPerRow == 0 || destinationBytesPerRow == 0 || uploadSize == 0 ||
        width == 0 || height == 0) {
        return false;
    }

    if (copyBytesPerRow > sourceBytesPerRow || copyBytesPerRow > destinationBytesPerRow) {
        return false;
    }

    id<MTLBuffer> stagingBuffer = [m_impl->device newBufferWithLength:uploadSize options:MTLResourceStorageModeShared];
    if (stagingBuffer == nil || stagingBuffer.contents == nullptr) {
        return false;
    }

    NSString* stagingLabel = uploadStagingLabel(label);
    if (stagingLabel != nil) {
        stagingBuffer.label = stagingLabel;
    }

    auto* destination = static_cast<std::byte*>(stagingBuffer.contents);
    const auto* source = static_cast<const std::byte*>(data);
    for (uint32_t row = 0; row < height; ++row) {
        std::memcpy(
            destination + static_cast<std::size_t>(row) * destinationBytesPerRow,
            source + static_cast<std::size_t>(row) * sourceBytesPerRow,
            copyBytesPerRow);
    }
    [m_impl->stagingBuffers addObject:stagingBuffer];

    [m_impl->blitEncoder copyFromBuffer:stagingBuffer
                           sourceOffset:0
                      sourceBytesPerRow:destinationBytesPerRow
                    sourceBytesPerImage:uploadSize
                             sourceSize:MTLSizeMake(width, height, 1)
                              toTexture:targetTexture
                       destinationSlice:0
                       destinationLevel:mipLevel
                      destinationOrigin:MTLOriginMake(0, 0, 0)];
    return true;
}

bool MetalResourceUploadBatch::commitAndWait()
{
    if (!isValid()) {
        return false;
    }

    [m_impl->blitEncoder endEncoding];
    m_impl->blitEncoder = nil;
    [m_impl->commandBuffer commit];
    [m_impl->commandBuffer waitUntilCompleted];

    const bool succeeded = m_impl->commandBuffer.status == MTLCommandBufferStatusCompleted;
    [m_impl->stagingBuffers removeAllObjects];
    m_impl->committed = true;
    return succeeded;
}

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
    MetalResourceUploadBatch uploadBatch(
        m_device,
        m_commandQueue,
        "Mesh2Splat Private Buffer Upload",
        "Mesh2Splat Private Buffer Upload Blit");
    return uploadBatch.uploadBufferToPrivate(data, size, destinationBuffer, label) &&
        uploadBatch.commitAndWait();
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
    MetalResourceUploadBatch uploadBatch(
        m_device,
        m_commandQueue,
        "Mesh2Splat Private Texture Upload",
        "Mesh2Splat Private Texture Upload Blit");
    return uploadBatch.uploadTexture2DToPrivate(
               data,
               sourceBytesPerRow,
               copyBytesPerRow,
               destinationBytesPerRow,
               uploadSize,
               width,
               height,
               mipLevel,
               destinationTexture,
               label) &&
        uploadBatch.commitAndWait();
}

} // namespace mesh2splat::metal
