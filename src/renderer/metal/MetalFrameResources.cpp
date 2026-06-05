#include "MetalFrameResources.hpp"

#include <algorithm>

namespace mesh2splat::metal {

MetalFrameResources::MetalFrameResources(uint32_t frameCount, std::size_t dynamicCapacity)
    : m_frames(std::max<uint32_t>(frameCount, 1))
    , m_dynamicCapacity(dynamicCapacity)
{
}

void MetalFrameResources::beginFrame()
{
    m_currentFrameIndex = static_cast<uint32_t>((m_currentFrameIndex + 1) % m_frames.size());
    m_frames[m_currentFrameIndex].dynamicOffset = 0;
    ++m_frameNumber;
}

MetalFrameResources::Allocation MetalFrameResources::allocateDynamic(std::size_t size, std::size_t alignment)
{
    if (size == 0 || m_frames.empty()) {
        return {};
    }

    FrameState& frame = m_frames[m_currentFrameIndex];
    const std::size_t alignedOffset = alignUp(frame.dynamicOffset, alignment);
    if (alignedOffset > m_dynamicCapacity || size > m_dynamicCapacity - alignedOffset) {
        return {};
    }

    frame.dynamicOffset = alignedOffset + size;
    return Allocation{m_currentFrameIndex, alignedOffset, size};
}

uint32_t MetalFrameResources::currentFrameIndex() const
{
    return m_currentFrameIndex;
}

uint64_t MetalFrameResources::frameNumber() const
{
    return m_frameNumber;
}

std::size_t MetalFrameResources::dynamicCapacity() const
{
    return m_dynamicCapacity;
}

std::size_t MetalFrameResources::dynamicUsedBytes() const
{
    return m_frames.empty() ? 0 : m_frames[m_currentFrameIndex].dynamicOffset;
}

std::size_t MetalFrameResources::alignUp(std::size_t value, std::size_t alignment)
{
    if (alignment <= 1) {
        return value;
    }

    const std::size_t remainder = value % alignment;
    return remainder == 0 ? value : value + (alignment - remainder);
}

} // namespace mesh2splat::metal
