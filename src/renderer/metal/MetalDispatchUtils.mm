#include "MetalDispatchUtils.hpp"

#import <Metal/Metal.h>

#include <algorithm>
#include <limits>
#include <sstream>

namespace mesh2splat::metal {
namespace {

std::size_t normalizedPositive(std::size_t value)
{
    return std::max<std::size_t>(1, value);
}

std::size_t saturatedMultiply(std::size_t lhs, std::size_t rhs)
{
    if (lhs == 0 || rhs == 0) {
        return 0;
    }

    const std::size_t maxValue = std::numeric_limits<std::size_t>::max();
    if (lhs > maxValue / rhs) {
        return maxValue;
    }

    return lhs * rhs;
}

std::size_t largestAxisIndex(const MetalDispatchSize& size)
{
    if (size.width >= size.height && size.width >= size.depth) {
        return 0;
    }
    if (size.height >= size.depth) {
        return 1;
    }
    return 2;
}

void clampLargestAxis(MetalDispatchSize& size, std::size_t maxTotalThreadsPerThreadgroup)
{
    const std::size_t axis = largestAxisIndex(size);
    if (axis == 0) {
        const std::size_t otherAxes = saturatedMultiply(size.height, size.depth);
        size.width = std::min(size.width, std::max<std::size_t>(1, maxTotalThreadsPerThreadgroup / otherAxes));
        return;
    }

    if (axis == 1) {
        const std::size_t otherAxes = saturatedMultiply(size.width, size.depth);
        size.height = std::min(size.height, std::max<std::size_t>(1, maxTotalThreadsPerThreadgroup / otherAxes));
        return;
    }

    const std::size_t otherAxes = saturatedMultiply(size.width, size.height);
    size.depth = std::min(size.depth, std::max<std::size_t>(1, maxTotalThreadsPerThreadgroup / otherAxes));
}

std::string sizeString(const MetalDispatchSize& size)
{
    std::ostringstream stream;
    stream << size.width << 'x' << size.height << 'x' << size.depth;
    return stream.str();
}

MetalDispatchDescriptor makeDispatchDescriptor(
    MetalDispatchSize threads,
    MetalDispatchSize preferredThreadsPerThreadgroup,
    std::size_t maxTotalThreadsPerThreadgroup,
    std::size_t threadExecutionWidth,
    uint32_t dimensions)
{
    MetalDispatchDescriptor descriptor;
    descriptor.threads = threads;
    descriptor.threadExecutionWidth = normalizedPositive(threadExecutionWidth);
    descriptor.maxTotalThreadsPerThreadgroup = normalizedPositive(maxTotalThreadsPerThreadgroup);
    descriptor.dimensions = std::max<uint32_t>(1, std::min<uint32_t>(dimensions, 3));
    descriptor.threadsPerThreadgroup = clampThreadgroupSize(
        preferredThreadsPerThreadgroup,
        descriptor.maxTotalThreadsPerThreadgroup,
        descriptor.threadExecutionWidth);

    if (descriptor.threads.isEmpty()) {
        descriptor.threadgroups = MetalDispatchSize(0, 0, 0);
        return descriptor;
    }

    descriptor.threadgroups = MetalDispatchSize(
        ceilDiv(descriptor.threads.width, descriptor.threadsPerThreadgroup.width),
        descriptor.dimensions >= 2
            ? ceilDiv(descriptor.threads.height, descriptor.threadsPerThreadgroup.height)
            : 1,
        descriptor.dimensions >= 3
            ? ceilDiv(descriptor.threads.depth, descriptor.threadsPerThreadgroup.depth)
            : 1);
    return descriptor;
}

} // namespace

bool MetalDispatchSize::isEmpty() const
{
    return width == 0 || height == 0 || depth == 0;
}

std::size_t MetalDispatchSize::elementCount() const
{
    if (isEmpty()) {
        return 0;
    }

    return saturatedMultiply(saturatedMultiply(width, height), depth);
}

bool MetalDispatchDescriptor::isEmpty() const
{
    return threads.isEmpty() || threadgroups.isEmpty();
}

std::string MetalDispatchDescriptor::debugString(const char* label) const
{
    return dispatchDebugString(*this, label);
}

std::size_t ceilDiv(std::size_t value, std::size_t divisor)
{
    if (value == 0 || divisor == 0) {
        return 0;
    }

    return 1 + ((value - 1) / divisor);
}

std::size_t dispatchElementCount(const MetalDispatchSize& size)
{
    return size.elementCount();
}

bool isEmptyDispatch(const MetalDispatchSize& threads)
{
    return threads.isEmpty();
}

std::size_t pipelineThreadExecutionWidth(void* computePipelineState)
{
    id<MTLComputePipelineState> pipelineState = (__bridge id<MTLComputePipelineState>)computePipelineState;
    if (pipelineState == nil) {
        return 1;
    }

    return normalizedPositive(static_cast<std::size_t>(pipelineState.threadExecutionWidth));
}

std::size_t pipelineMaxTotalThreadsPerThreadgroup(void* computePipelineState)
{
    id<MTLComputePipelineState> pipelineState = (__bridge id<MTLComputePipelineState>)computePipelineState;
    if (pipelineState == nil) {
        return 1;
    }

    return normalizedPositive(static_cast<std::size_t>(pipelineState.maxTotalThreadsPerThreadgroup));
}

std::size_t clampThreadgroupThreadCount(
    std::size_t preferredThreads,
    std::size_t maxTotalThreadsPerThreadgroup,
    std::size_t threadExecutionWidth)
{
    const std::size_t executionWidth = normalizedPositive(threadExecutionWidth);
    const std::size_t maxThreads = normalizedPositive(maxTotalThreadsPerThreadgroup);
    std::size_t threadCount = normalizedPositive(preferredThreads);

    if (maxThreads >= executionWidth) {
        threadCount = std::max(threadCount, executionWidth);
    }

    threadCount = std::min(threadCount, maxThreads);
    if (maxThreads < executionWidth) {
        return threadCount;
    }

    const std::size_t alignedThreadCount = threadCount - (threadCount % executionWidth);
    return alignedThreadCount == 0 ? std::min(executionWidth, maxThreads) : alignedThreadCount;
}

MetalDispatchSize clampThreadgroupSize(
    MetalDispatchSize preferredThreadsPerThreadgroup,
    std::size_t maxTotalThreadsPerThreadgroup,
    std::size_t threadExecutionWidth)
{
    MetalDispatchSize clamped(
        normalizedPositive(preferredThreadsPerThreadgroup.width),
        normalizedPositive(preferredThreadsPerThreadgroup.height),
        normalizedPositive(preferredThreadsPerThreadgroup.depth));

    const std::size_t maxThreads = normalizedPositive(maxTotalThreadsPerThreadgroup);
    if (clamped.height == 1 && clamped.depth == 1) {
        clamped.width = clampThreadgroupThreadCount(clamped.width, maxThreads, threadExecutionWidth);
        return clamped;
    }

    while (clamped.elementCount() > maxThreads) {
        const MetalDispatchSize previous = clamped;
        clampLargestAxis(clamped, maxThreads);
        if (clamped.width == previous.width &&
            clamped.height == previous.height &&
            clamped.depth == previous.depth) {
            break;
        }
    }

    return clamped;
}

std::size_t computeThreadgroupSize1D(void* computePipelineState, std::size_t preferredThreads)
{
    return clampThreadgroupThreadCount(
        preferredThreads,
        pipelineMaxTotalThreadsPerThreadgroup(computePipelineState),
        pipelineThreadExecutionWidth(computePipelineState));
}

MetalDispatchDescriptor makeDispatchDescriptor1D(
    std::size_t threadCount,
    std::size_t preferredThreadsPerThreadgroup,
    std::size_t maxTotalThreadsPerThreadgroup,
    std::size_t threadExecutionWidth)
{
    return makeDispatchDescriptor(
        MetalDispatchSize(threadCount, 1, 1),
        MetalDispatchSize(preferredThreadsPerThreadgroup, 1, 1),
        maxTotalThreadsPerThreadgroup,
        threadExecutionWidth,
        1);
}

MetalDispatchDescriptor makeDispatchDescriptor1D(
    void* computePipelineState,
    std::size_t threadCount,
    std::size_t preferredThreadsPerThreadgroup)
{
    return makeDispatchDescriptor1D(
        threadCount,
        preferredThreadsPerThreadgroup,
        pipelineMaxTotalThreadsPerThreadgroup(computePipelineState),
        pipelineThreadExecutionWidth(computePipelineState));
}

MetalDispatchDescriptor makeDispatchDescriptor2D(
    std::size_t width,
    std::size_t height,
    MetalDispatchSize preferredThreadsPerThreadgroup,
    std::size_t maxTotalThreadsPerThreadgroup,
    std::size_t threadExecutionWidth)
{
    return makeDispatchDescriptor(
        MetalDispatchSize(width, height, 1),
        MetalDispatchSize(
            preferredThreadsPerThreadgroup.width,
            preferredThreadsPerThreadgroup.height,
            1),
        maxTotalThreadsPerThreadgroup,
        threadExecutionWidth,
        2);
}

MetalDispatchDescriptor makeDispatchDescriptor2D(
    void* computePipelineState,
    std::size_t width,
    std::size_t height,
    MetalDispatchSize preferredThreadsPerThreadgroup)
{
    return makeDispatchDescriptor2D(
        width,
        height,
        preferredThreadsPerThreadgroup,
        pipelineMaxTotalThreadsPerThreadgroup(computePipelineState),
        pipelineThreadExecutionWidth(computePipelineState));
}

MetalDispatchDescriptor makeDispatchDescriptor3D(
    std::size_t width,
    std::size_t height,
    std::size_t depth,
    MetalDispatchSize preferredThreadsPerThreadgroup,
    std::size_t maxTotalThreadsPerThreadgroup,
    std::size_t threadExecutionWidth)
{
    return makeDispatchDescriptor(
        MetalDispatchSize(width, height, depth),
        preferredThreadsPerThreadgroup,
        maxTotalThreadsPerThreadgroup,
        threadExecutionWidth,
        3);
}

MetalDispatchDescriptor makeDispatchDescriptor3D(
    void* computePipelineState,
    std::size_t width,
    std::size_t height,
    std::size_t depth,
    MetalDispatchSize preferredThreadsPerThreadgroup)
{
    return makeDispatchDescriptor3D(
        width,
        height,
        depth,
        preferredThreadsPerThreadgroup,
        pipelineMaxTotalThreadsPerThreadgroup(computePipelineState),
        pipelineThreadExecutionWidth(computePipelineState));
}

std::string dispatchDebugString(const MetalDispatchDescriptor& descriptor, const char* label)
{
    std::ostringstream stream;
    if (label != nullptr && label[0] != '\0') {
        stream << label << ": ";
    }

    stream << "dimensions=" << descriptor.dimensions
           << ", threads=" << sizeString(descriptor.threads)
           << ", threadsPerThreadgroup=" << sizeString(descriptor.threadsPerThreadgroup)
           << ", threadgroups=" << sizeString(descriptor.threadgroups)
           << ", threadExecutionWidth=" << descriptor.threadExecutionWidth
           << ", maxTotalThreadsPerThreadgroup=" << descriptor.maxTotalThreadsPerThreadgroup
           << ", totalThreads=" << descriptor.threads.elementCount()
           << ", empty=" << (descriptor.isEmpty() ? "true" : "false");
    return stream.str();
}

} // namespace mesh2splat::metal
