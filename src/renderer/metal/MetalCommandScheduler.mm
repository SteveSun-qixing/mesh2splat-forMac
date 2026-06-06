#include "MetalCommandScheduler.hpp"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

namespace mesh2splat::metal {
namespace {

NSString* labelString(const char* label)
{
    return label == nullptr ? nil : [NSString stringWithUTF8String:label];
}

std::string utf8String(NSString* string)
{
    return string == nil || string.UTF8String == nullptr ? std::string{} : string.UTF8String;
}

id<MTLCommandBuffer> nativeCommandBuffer(void* commandBuffer)
{
    return (__bridge id<MTLCommandBuffer>)commandBuffer;
}

} // namespace

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

    setCommandBufferLabel((__bridge void*)commandBuffer, label);
    return (__bridge void*)commandBuffer;
}

bool MetalCommandScheduler::commit(void* commandBuffer) const
{
    return commitCommandBuffer(commandBuffer);
}

bool MetalCommandScheduler::commitAndWait(void* commandBuffer) const
{
    if (!commitCommandBuffer(commandBuffer)) {
        return false;
    }

    return waitUntilCompleted(commandBuffer);
}

bool MetalCommandScheduler::setCommandBufferLabel(void* commandBuffer, const char* label)
{
    id<MTLCommandBuffer> nativeBuffer = nativeCommandBuffer(commandBuffer);
    if (nativeBuffer == nil) {
        return false;
    }

    nativeBuffer.label = labelString(label);
    return label == nullptr || nativeBuffer.label != nil;
}

std::string MetalCommandScheduler::commandBufferLabel(void* commandBuffer)
{
    id<MTLCommandBuffer> nativeBuffer = nativeCommandBuffer(commandBuffer);
    return nativeBuffer == nil ? std::string{} : utf8String(nativeBuffer.label);
}

bool MetalCommandScheduler::commitCommandBuffer(void* commandBuffer)
{
    id<MTLCommandBuffer> nativeBuffer = nativeCommandBuffer(commandBuffer);
    if (nativeBuffer == nil) {
        return false;
    }

    [nativeBuffer commit];
    return true;
}

bool MetalCommandScheduler::waitUntilCompleted(void* commandBuffer)
{
    id<MTLCommandBuffer> nativeBuffer = nativeCommandBuffer(commandBuffer);
    if (nativeBuffer == nil) {
        return false;
    }

    [nativeBuffer waitUntilCompleted];
    return nativeBuffer.status == MTLCommandBufferStatusCompleted;
}

bool MetalCommandScheduler::presentDrawable(void* commandBuffer, void* drawable)
{
    id<MTLCommandBuffer> nativeBuffer = nativeCommandBuffer(commandBuffer);
    id<MTLDrawable> nativeDrawable = (__bridge id<MTLDrawable>)drawable;
    if (nativeBuffer == nil || nativeDrawable == nil) {
        return false;
    }

    [nativeBuffer presentDrawable:nativeDrawable];
    return true;
}

bool MetalCommandScheduler::commandBufferCompleted(void* commandBuffer)
{
    id<MTLCommandBuffer> nativeBuffer = nativeCommandBuffer(commandBuffer);
    return nativeBuffer != nil && nativeBuffer.status == MTLCommandBufferStatusCompleted;
}

int MetalCommandScheduler::commandBufferStatus(void* commandBuffer)
{
    id<MTLCommandBuffer> nativeBuffer = nativeCommandBuffer(commandBuffer);
    return nativeBuffer == nil ? -1 : static_cast<int>(nativeBuffer.status);
}

double MetalCommandScheduler::commandBufferGpuMilliseconds(void* commandBuffer)
{
    id<MTLCommandBuffer> nativeBuffer = nativeCommandBuffer(commandBuffer);
    if (nativeBuffer == nil || nativeBuffer.status != MTLCommandBufferStatusCompleted) {
        return 0.0;
    }

    const CFTimeInterval startTime = nativeBuffer.GPUStartTime;
    const CFTimeInterval endTime = nativeBuffer.GPUEndTime;
    if (startTime <= 0.0 || endTime <= startTime) {
        return 0.0;
    }

    return static_cast<double>(endTime - startTime) * 1000.0;
}

std::string MetalCommandScheduler::commandBufferStatusDescription(int status)
{
    switch (static_cast<MTLCommandBufferStatus>(status)) {
    case MTLCommandBufferStatusNotEnqueued:
        return "not enqueued";
    case MTLCommandBufferStatusEnqueued:
        return "enqueued";
    case MTLCommandBufferStatusCommitted:
        return "committed";
    case MTLCommandBufferStatusScheduled:
        return "scheduled";
    case MTLCommandBufferStatusCompleted:
        return "completed";
    case MTLCommandBufferStatusError:
        return "error";
    }

    return "unknown";
}

std::string MetalCommandScheduler::commandBufferStatusDescription(void* commandBuffer)
{
    return commandBufferStatusDescription(commandBufferStatus(commandBuffer));
}

std::string MetalCommandScheduler::commandBufferErrorDescription(void* commandBuffer)
{
    id<MTLCommandBuffer> nativeBuffer = nativeCommandBuffer(commandBuffer);
    return nativeBuffer == nil || nativeBuffer.error == nil ? std::string{} : utf8String(nativeBuffer.error.localizedDescription);
}

MetalCommandBufferDiagnostics MetalCommandScheduler::commandBufferDiagnostics(void* commandBuffer)
{
    id<MTLCommandBuffer> nativeBuffer = nativeCommandBuffer(commandBuffer);
    MetalCommandBufferDiagnostics diagnostics;
    diagnostics.valid = nativeBuffer != nil;
    if (!diagnostics.valid) {
        diagnostics.statusDescription = commandBufferStatusDescription(diagnostics.status);
        return diagnostics;
    }

    diagnostics.status = static_cast<int>(nativeBuffer.status);
    diagnostics.completed = nativeBuffer.status == MTLCommandBufferStatusCompleted;
    diagnostics.failed = nativeBuffer.status == MTLCommandBufferStatusError;
    diagnostics.gpuMilliseconds = commandBufferGpuMilliseconds(commandBuffer);
    diagnostics.label = commandBufferLabel(commandBuffer);
    diagnostics.statusDescription = commandBufferStatusDescription(diagnostics.status);
    diagnostics.errorDescription = commandBufferErrorDescription(commandBuffer);
    return diagnostics;
}

} // namespace mesh2splat::metal
