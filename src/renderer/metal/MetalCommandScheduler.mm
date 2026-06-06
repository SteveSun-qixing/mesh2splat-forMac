#include "MetalCommandScheduler.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

namespace mesh2splat::metal {

MetalCommandScheduler::MetalCommandScheduler(void* commandQueue)
    : m_commandQueue(commandQueue)
{
}

void* MetalCommandScheduler::createCommandBuffer(const char* label) const
{
    id<MTLCommandQueue> commandQueue = (__bridge id<MTLCommandQueue>)m_commandQueue;
    if (commandQueue == nil) {
        return nullptr;
    }

    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    if (commandBuffer == nil) {
        return nullptr;
    }

    if (label != nullptr) {
        commandBuffer.label = [NSString stringWithUTF8String:label];
    }
    return (__bridge void*)commandBuffer;
}

bool MetalCommandScheduler::commit(void* commandBuffer) const
{
    id<MTLCommandBuffer> nativeCommandBuffer = (__bridge id<MTLCommandBuffer>)commandBuffer;
    if (nativeCommandBuffer == nil) {
        return false;
    }

    [nativeCommandBuffer commit];
    return true;
}

bool MetalCommandScheduler::commitAndWait(void* commandBuffer) const
{
    id<MTLCommandBuffer> nativeCommandBuffer = (__bridge id<MTLCommandBuffer>)commandBuffer;
    if (nativeCommandBuffer == nil) {
        return false;
    }

    [nativeCommandBuffer commit];
    [nativeCommandBuffer waitUntilCompleted];
    return nativeCommandBuffer.status == MTLCommandBufferStatusCompleted;
}

bool MetalCommandScheduler::commandBufferCompleted(void* commandBuffer)
{
    id<MTLCommandBuffer> nativeCommandBuffer = (__bridge id<MTLCommandBuffer>)commandBuffer;
    return nativeCommandBuffer != nil && nativeCommandBuffer.status == MTLCommandBufferStatusCompleted;
}

} // namespace mesh2splat::metal
