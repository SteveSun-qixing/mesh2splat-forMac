#include "MetalDispatchUtils.hpp"

#import <Metal/Metal.h>

#include <algorithm>

namespace mesh2splat::metal {

std::size_t computeThreadgroupSize1D(void* computePipelineState, std::size_t preferredThreads)
{
    id<MTLComputePipelineState> pipelineState = (__bridge id<MTLComputePipelineState>)computePipelineState;
    if (pipelineState == nil) {
        return 1;
    }

    const std::size_t executionWidth = std::max<std::size_t>(1, pipelineState.threadExecutionWidth);
    const std::size_t maxThreads = std::max<std::size_t>(1, pipelineState.maxTotalThreadsPerThreadgroup);
    const std::size_t preferred = std::max(preferredThreads, executionWidth);
    std::size_t threadCount = std::min(preferred, maxThreads);
    threadCount -= threadCount % executionWidth;
    if (threadCount == 0) {
        threadCount = std::min(executionWidth, maxThreads);
    }

    return std::max<std::size_t>(1, threadCount);
}

} // namespace mesh2splat::metal
