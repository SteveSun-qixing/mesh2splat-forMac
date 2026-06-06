#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace mesh2splat::metal {

struct MetalDispatchSize {
    std::size_t width = 0;
    std::size_t height = 1;
    std::size_t depth = 1;

    constexpr MetalDispatchSize() = default;
    constexpr MetalDispatchSize(
        std::size_t widthValue,
        std::size_t heightValue = 1,
        std::size_t depthValue = 1)
        : width(widthValue)
        , height(heightValue)
        , depth(depthValue)
    {
    }

    bool isEmpty() const;
    std::size_t elementCount() const;
};

struct MetalDispatchDescriptor {
    MetalDispatchSize threads;
    MetalDispatchSize threadsPerThreadgroup = MetalDispatchSize(1, 1, 1);
    MetalDispatchSize threadgroups;
    std::size_t threadExecutionWidth = 1;
    std::size_t maxTotalThreadsPerThreadgroup = 1;
    uint32_t dimensions = 1;

    bool isEmpty() const;
    std::string debugString(const char* label = nullptr) const;
};

std::size_t ceilDiv(std::size_t value, std::size_t divisor);
std::size_t dispatchElementCount(const MetalDispatchSize& size);
bool isEmptyDispatch(const MetalDispatchSize& threads);

std::size_t pipelineThreadExecutionWidth(void* computePipelineState);
std::size_t pipelineMaxTotalThreadsPerThreadgroup(void* computePipelineState);

std::size_t clampThreadgroupThreadCount(
    std::size_t preferredThreads,
    std::size_t maxTotalThreadsPerThreadgroup,
    std::size_t threadExecutionWidth = 1);

MetalDispatchSize clampThreadgroupSize(
    MetalDispatchSize preferredThreadsPerThreadgroup,
    std::size_t maxTotalThreadsPerThreadgroup,
    std::size_t threadExecutionWidth = 1);

std::size_t computeThreadgroupSize1D(void* computePipelineState, std::size_t preferredThreads = 256);

MetalDispatchDescriptor makeDispatchDescriptor1D(
    std::size_t threadCount,
    std::size_t preferredThreadsPerThreadgroup,
    std::size_t maxTotalThreadsPerThreadgroup,
    std::size_t threadExecutionWidth = 1);

MetalDispatchDescriptor makeDispatchDescriptor1D(
    void* computePipelineState,
    std::size_t threadCount,
    std::size_t preferredThreadsPerThreadgroup = 256);

MetalDispatchDescriptor makeDispatchDescriptor2D(
    std::size_t width,
    std::size_t height,
    MetalDispatchSize preferredThreadsPerThreadgroup,
    std::size_t maxTotalThreadsPerThreadgroup,
    std::size_t threadExecutionWidth = 1);

MetalDispatchDescriptor makeDispatchDescriptor2D(
    void* computePipelineState,
    std::size_t width,
    std::size_t height,
    MetalDispatchSize preferredThreadsPerThreadgroup = MetalDispatchSize(16, 16, 1));

MetalDispatchDescriptor makeDispatchDescriptor3D(
    std::size_t width,
    std::size_t height,
    std::size_t depth,
    MetalDispatchSize preferredThreadsPerThreadgroup,
    std::size_t maxTotalThreadsPerThreadgroup,
    std::size_t threadExecutionWidth = 1);

MetalDispatchDescriptor makeDispatchDescriptor3D(
    void* computePipelineState,
    std::size_t width,
    std::size_t height,
    std::size_t depth,
    MetalDispatchSize preferredThreadsPerThreadgroup = MetalDispatchSize(8, 8, 4));

std::string dispatchDebugString(const MetalDispatchDescriptor& descriptor, const char* label = nullptr);

} // namespace mesh2splat::metal
