#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace mesh2splat::metal {

class MetalFrameResources {
public:
    static constexpr std::size_t kDefaultDynamicAlignment = 256;

    enum class FramePhase : uint8_t {
        Available,
        Encoding,
        Submitted,
        Completed,
    };

    struct Allocation {
        uint32_t frameIndex = 0;
        std::size_t offset = 0;
        std::size_t size = 0;
        uint64_t frameNumber = 0;
        std::size_t requestedSize = 0;
        std::size_t alignment = 1;
        std::size_t padding = 0;
        std::size_t capacityBefore = 0;
        std::size_t capacityAfter = 0;
        bool grewCapacity = false;
        uint64_t allocationSerial = 0;
        std::string debugLabel;

        bool isValid() const { return size > 0; }
    };

    struct RingFrameMetadata {
        uint32_t frameIndex = 0;
        uint64_t frameNumber = 0;
        std::size_t dynamicOffset = 0;
        std::size_t dynamicCapacity = 0;
        std::size_t allocationCount = 0;
        std::size_t highWatermark = 0;
        bool isCurrent = false;
        bool isInFlight = false;
        FramePhase phase = FramePhase::Available;
        uint64_t submissionSerial = 0;
        uint64_t completionSerial = 0;
        std::string debugLabel;
    };

    struct Diagnostics {
        uint32_t frameCount = 0;
        uint32_t currentFrameIndex = 0;
        uint64_t frameNumber = 0;
        std::size_t inFlightFrameCount = 0;
        std::size_t dynamicCapacity = 0;
        std::size_t dynamicUsedBytes = 0;
        std::size_t dynamicRemainingBytes = 0;
        std::size_t dynamicHighWatermarkBytes = 0;
        std::size_t dynamicCapacityGrowthCount = 0;
        std::size_t lastRequiredCapacity = 0;
        std::size_t totalDynamicAllocationCount = 0;
        std::size_t reusedSubmittedFrameCount = 0;
        RingFrameMetadata currentFrame;
        Allocation lastAllocation;
        std::string debugLabel;
        std::string lastMessage;
    };

    explicit MetalFrameResources(uint32_t frameCount = 3, std::size_t dynamicCapacity = 4 * 1024 * 1024);

    void beginFrame();
    void beginFrame(const char* debugLabel);
    Allocation allocateDynamic(std::size_t size, std::size_t alignment);
    Allocation allocateDynamic(std::size_t size, std::size_t alignment, const char* debugLabel);

    void markCurrentFrameSubmitted();
    void markFrameSubmitted(uint32_t frameIndex);
    void markFrameSubmitted(uint32_t frameIndex, uint64_t submissionSerial);
    void markCurrentFrameCompleted();
    void markFrameCompleted(uint32_t frameIndex, uint64_t completionSerial = 0);
    void resetFrame(uint32_t frameIndex);

    RingFrameMetadata currentFrameMetadata() const;
    RingFrameMetadata frameMetadata(uint32_t frameIndex) const;
    uint32_t normalizeFrameIndex(uint32_t frameIndex) const;
    bool isValidFrameIndex(uint32_t frameIndex) const;
    bool isCurrentFrame(uint32_t frameIndex) const;
    bool isFrameInFlight(uint32_t frameIndex) const;
    std::size_t inFlightFrameCount() const;
    uint32_t currentFrameIndex() const;
    uint32_t frameCount() const;
    uint32_t maxInFlightFrames() const;
    uint64_t frameNumber() const;
    std::size_t dynamicCapacity() const;
    std::size_t dynamicUsedBytes() const;
    std::size_t dynamicRemainingBytes() const;
    std::size_t dynamicHighWatermarkBytes() const;
    std::size_t dynamicCapacityGrowthCount() const;
    std::size_t lastRequiredCapacity() const;
    std::size_t currentFrameAllocationCount() const;
    std::size_t totalDynamicAllocationCount() const;
    std::vector<Allocation> currentFrameAllocations() const;
    std::vector<Allocation> frameAllocations(uint32_t frameIndex) const;
    bool reserveDynamicCapacity(std::size_t requiredCapacity);
    const Allocation& lastAllocation() const;
    Diagnostics diagnostics() const;
    const std::string& lastDiagnostic() const;
    void setDebugLabel(const char* label);
    const std::string& debugLabel() const;
    std::string describeCurrentFrame() const;
    std::string describeFrame(uint32_t frameIndex) const;

    static std::size_t normalizeAlignment(std::size_t alignment);
    static std::size_t alignOffset(std::size_t offset, std::size_t alignment);
    static std::size_t alignedSize(std::size_t size, std::size_t alignment);
    static bool isAligned(std::size_t offset, std::size_t alignment);
    static const char* framePhaseName(FramePhase phase);

private:
    struct FrameState {
        std::size_t dynamicOffset = 0;
        std::size_t allocationCount = 0;
        std::size_t highWatermark = 0;
        uint64_t frameNumber = 0;
        bool isCurrent = false;
        FramePhase phase = FramePhase::Available;
        uint64_t submissionSerial = 0;
        uint64_t completionSerial = 0;
        std::string debugLabel;
        std::vector<Allocation> allocations;
    };

    bool ensureDynamicCapacity(std::size_t requiredCapacity);
    std::size_t nextDynamicCapacity(std::size_t requiredCapacity) const;
    std::string makeFrameDiagnostic(uint32_t frameIndex) const;

    std::vector<FrameState> m_frames;
    uint32_t m_currentFrameIndex = 0;
    uint64_t m_frameNumber = 0;
    std::size_t m_dynamicCapacity = 0;
    std::size_t m_dynamicHighWatermark = 0;
    std::size_t m_dynamicCapacityGrowthCount = 0;
    std::size_t m_lastRequiredCapacity = 0;
    uint64_t m_allocationSerial = 0;
    uint64_t m_submissionSerial = 0;
    uint64_t m_completionSerial = 0;
    std::size_t m_reusedSubmittedFrameCount = 0;
    Allocation m_lastAllocation;
    std::string m_debugLabel;
    std::string m_lastDiagnostic;
};

} // namespace mesh2splat::metal
