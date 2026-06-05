#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace mesh2splat::metal {

class MetalFrameResources {
public:
    struct Allocation {
        uint32_t frameIndex = 0;
        std::size_t offset = 0;
        std::size_t size = 0;

        bool isValid() const { return size > 0; }
    };

    explicit MetalFrameResources(uint32_t frameCount = 3, std::size_t dynamicCapacity = 4 * 1024 * 1024);

    void beginFrame();
    Allocation allocateDynamic(std::size_t size, std::size_t alignment);

    uint32_t currentFrameIndex() const;
    uint64_t frameNumber() const;
    std::size_t dynamicCapacity() const;
    std::size_t dynamicUsedBytes() const;

private:
    struct FrameState {
        std::size_t dynamicOffset = 0;
    };

    static std::size_t alignUp(std::size_t value, std::size_t alignment);

    std::vector<FrameState> m_frames;
    uint32_t m_currentFrameIndex = 0;
    uint64_t m_frameNumber = 0;
    std::size_t m_dynamicCapacity = 0;
};

} // namespace mesh2splat::metal
