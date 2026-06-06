#include "MetalFrameResources.hpp"

#include <algorithm>
#include <limits>
#include <sstream>

namespace mesh2splat::metal {

MetalFrameResources::MetalFrameResources(uint32_t frameCount, std::size_t dynamicCapacity)
    : m_frames(std::max<uint32_t>(frameCount, 1))
    , m_dynamicCapacity(dynamicCapacity)
    , m_debugLabel("MetalFrameResources")
{
    m_frames[m_currentFrameIndex].isCurrent = true;
    m_frames[m_currentFrameIndex].phase = FramePhase::Encoding;
    m_frames[m_currentFrameIndex].debugLabel = m_debugLabel;
    m_lastDiagnostic = makeFrameDiagnostic(m_currentFrameIndex);
}

void MetalFrameResources::beginFrame()
{
    beginFrame(nullptr);
}

void MetalFrameResources::beginFrame(const char* debugLabel)
{
    if (m_frames.empty()) {
        m_lastAllocation = {};
        m_lastDiagnostic = "MetalFrameResources has no ring frames.";
        return;
    }

    FrameState& previousFrame = m_frames[m_currentFrameIndex];
    previousFrame.isCurrent = false;
    if (previousFrame.phase == FramePhase::Encoding) {
        previousFrame.phase = FramePhase::Completed;
    }

    const uint32_t preferredFrameIndex = static_cast<uint32_t>((m_currentFrameIndex + 1) % m_frames.size());
    uint32_t nextFrameIndex = preferredFrameIndex;
    for (std::size_t candidateOffset = 0; candidateOffset < m_frames.size(); ++candidateOffset) {
        const uint32_t candidateFrameIndex =
            static_cast<uint32_t>((preferredFrameIndex + candidateOffset) % m_frames.size());
        if (m_frames[candidateFrameIndex].phase != FramePhase::Submitted) {
            nextFrameIndex = candidateFrameIndex;
            break;
        }
    }

    m_currentFrameIndex = nextFrameIndex;
    ++m_frameNumber;

    FrameState& frame = m_frames[m_currentFrameIndex];
    const bool reusedSubmittedFrame = frame.phase == FramePhase::Submitted;
    frame.dynamicOffset = 0;
    frame.allocationCount = 0;
    frame.allocations.clear();
    frame.frameNumber = m_frameNumber;
    frame.isCurrent = true;
    frame.phase = FramePhase::Encoding;
    frame.submissionSerial = 0;
    frame.completionSerial = 0;
    frame.debugLabel = debugLabel != nullptr ? debugLabel : m_debugLabel;

    m_lastAllocation = {};
    m_lastDiagnostic = makeFrameDiagnostic(m_currentFrameIndex);
    if (reusedSubmittedFrame) {
        ++m_reusedSubmittedFrameCount;
        m_lastDiagnostic += " warning=reusedSubmittedFrameBeforeCompletion";
    }
}

MetalFrameResources::Allocation MetalFrameResources::allocateDynamic(std::size_t size, std::size_t alignment)
{
    return allocateDynamic(size, alignment, nullptr);
}

MetalFrameResources::Allocation MetalFrameResources::allocateDynamic(
    std::size_t size,
    std::size_t alignment,
    const char* debugLabel)
{
    if (size == 0 || m_frames.empty()) {
        m_lastAllocation = {};
        m_lastDiagnostic = "MetalFrameResources dynamic allocation rejected: size is zero or no ring frames are available.";
        return {};
    }

    FrameState& frame = m_frames[m_currentFrameIndex];
    const std::size_t normalizedAlignment = normalizeAlignment(alignment);
    const std::size_t originalOffset = frame.dynamicOffset;
    const std::size_t alignedOffset = alignOffset(originalOffset, normalizedAlignment);
    if (alignedOffset == std::numeric_limits<std::size_t>::max() ||
        alignedOffset > std::numeric_limits<std::size_t>::max() - size) {
        m_lastAllocation = {};
        std::ostringstream stream;
        stream << "MetalFrameResources dynamic allocation overflow: frameIndex=" << m_currentFrameIndex
               << " frameNumber=" << m_frameNumber
               << " requestedSize=" << size
               << " alignment=" << normalizedAlignment
               << " currentOffset=" << originalOffset
               << " alignedOffset=" << alignedOffset
               << " capacity=" << m_dynamicCapacity;
        m_lastDiagnostic = stream.str();
        return {};
    }

    const std::size_t requiredCapacity = alignedOffset + size;
    const std::size_t capacityBefore = m_dynamicCapacity;
    const bool grewCapacity = ensureDynamicCapacity(requiredCapacity);
    const std::size_t capacityAfter = m_dynamicCapacity;

    frame.dynamicOffset = alignedOffset + size;
    ++frame.allocationCount;
    frame.highWatermark = std::max(frame.highWatermark, frame.dynamicOffset);
    m_dynamicHighWatermark = std::max(m_dynamicHighWatermark, frame.dynamicOffset);

    const uint64_t allocationSerial = ++m_allocationSerial;
    m_lastAllocation = Allocation{
        m_currentFrameIndex,
        alignedOffset,
        size,
        m_frameNumber,
        size,
        normalizedAlignment,
        alignedOffset - originalOffset,
        capacityBefore,
        capacityAfter,
        grewCapacity,
        allocationSerial,
        debugLabel != nullptr ? debugLabel : std::string{},
    };
    frame.allocations.push_back(m_lastAllocation);
    m_lastDiagnostic = makeFrameDiagnostic(m_currentFrameIndex);
    return m_lastAllocation;
}

void MetalFrameResources::markCurrentFrameSubmitted()
{
    markFrameSubmitted(m_currentFrameIndex);
}

void MetalFrameResources::markFrameSubmitted(uint32_t frameIndex)
{
    markFrameSubmitted(frameIndex, 0);
}

void MetalFrameResources::markFrameSubmitted(uint32_t frameIndex, uint64_t submissionSerial)
{
    if (m_frames.empty()) {
        m_lastDiagnostic = "MetalFrameResources submit ignored: no ring frames are available.";
        return;
    }

    const uint32_t normalizedFrameIndex = normalizeFrameIndex(frameIndex);
    FrameState& frame = m_frames[normalizedFrameIndex];
    const uint64_t resolvedSerial = submissionSerial == 0 ? ++m_submissionSerial : submissionSerial;
    m_submissionSerial = std::max(m_submissionSerial, resolvedSerial);
    frame.phase = FramePhase::Submitted;
    frame.submissionSerial = resolvedSerial;
    frame.completionSerial = 0;
    m_lastDiagnostic = makeFrameDiagnostic(normalizedFrameIndex);
}

void MetalFrameResources::markCurrentFrameCompleted()
{
    markFrameCompleted(m_currentFrameIndex);
}

void MetalFrameResources::markFrameCompleted(uint32_t frameIndex, uint64_t completionSerial)
{
    if (m_frames.empty()) {
        m_lastDiagnostic = "MetalFrameResources completion ignored: no ring frames are available.";
        return;
    }

    const uint32_t normalizedFrameIndex = normalizeFrameIndex(frameIndex);
    FrameState& frame = m_frames[normalizedFrameIndex];
    const uint64_t nextCompletionSerial = m_completionSerial == std::numeric_limits<uint64_t>::max() ?
        m_completionSerial :
        m_completionSerial + 1;
    const uint64_t resolvedSerial = completionSerial == 0 ?
        std::max(frame.submissionSerial, std::max(m_submissionSerial, nextCompletionSerial)) :
        completionSerial;
    m_completionSerial = std::max(m_completionSerial, resolvedSerial);
    frame.phase = FramePhase::Completed;
    frame.completionSerial = resolvedSerial;
    m_lastDiagnostic = makeFrameDiagnostic(normalizedFrameIndex);
}

void MetalFrameResources::resetFrame(uint32_t frameIndex)
{
    if (m_frames.empty()) {
        m_lastDiagnostic = "MetalFrameResources reset ignored: no ring frames are available.";
        return;
    }

    const uint32_t normalizedFrameIndex = normalizeFrameIndex(frameIndex);
    FrameState& frame = m_frames[normalizedFrameIndex];
    const bool wasCurrent = frame.isCurrent;
    frame.dynamicOffset = 0;
    frame.allocationCount = 0;
    frame.allocations.clear();
    frame.frameNumber = wasCurrent ? m_frameNumber : 0;
    frame.phase = wasCurrent ? FramePhase::Encoding : FramePhase::Available;
    frame.submissionSerial = 0;
    frame.completionSerial = 0;
    frame.debugLabel = wasCurrent ? m_debugLabel : std::string{};
    m_lastAllocation = {};
    m_lastDiagnostic = makeFrameDiagnostic(normalizedFrameIndex);
}

MetalFrameResources::RingFrameMetadata MetalFrameResources::currentFrameMetadata() const
{
    return frameMetadata(m_currentFrameIndex);
}

MetalFrameResources::RingFrameMetadata MetalFrameResources::frameMetadata(uint32_t frameIndex) const
{
    if (m_frames.empty()) {
        return {};
    }

    const uint32_t normalizedFrameIndex = normalizeFrameIndex(frameIndex);
    const FrameState& frame = m_frames[normalizedFrameIndex];
    return RingFrameMetadata{
        normalizedFrameIndex,
        frame.frameNumber,
        frame.dynamicOffset,
        m_dynamicCapacity,
        frame.allocationCount,
        frame.highWatermark,
        frame.isCurrent,
        isFrameInFlight(normalizedFrameIndex),
        frame.phase,
        frame.submissionSerial,
        frame.completionSerial,
        frame.debugLabel,
    };
}

uint32_t MetalFrameResources::normalizeFrameIndex(uint32_t frameIndex) const
{
    return m_frames.empty() ? 0 : static_cast<uint32_t>(frameIndex % m_frames.size());
}

bool MetalFrameResources::isValidFrameIndex(uint32_t frameIndex) const
{
    return frameIndex < m_frames.size();
}

bool MetalFrameResources::isCurrentFrame(uint32_t frameIndex) const
{
    return !m_frames.empty() && normalizeFrameIndex(frameIndex) == m_currentFrameIndex;
}

bool MetalFrameResources::isFrameInFlight(uint32_t frameIndex) const
{
    if (m_frames.empty()) {
        return false;
    }

    return m_frames[normalizeFrameIndex(frameIndex)].phase == FramePhase::Submitted;
}

std::size_t MetalFrameResources::inFlightFrameCount() const
{
    std::size_t count = 0;
    for (const FrameState& frame : m_frames) {
        if (frame.phase == FramePhase::Submitted) {
            ++count;
        }
    }
    return count;
}

uint32_t MetalFrameResources::currentFrameIndex() const
{
    return m_currentFrameIndex;
}

uint32_t MetalFrameResources::frameCount() const
{
    return static_cast<uint32_t>(m_frames.size());
}

uint32_t MetalFrameResources::maxInFlightFrames() const
{
    return frameCount();
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

std::size_t MetalFrameResources::dynamicRemainingBytes() const
{
    const std::size_t usedBytes = dynamicUsedBytes();
    return usedBytes > m_dynamicCapacity ? 0 : m_dynamicCapacity - usedBytes;
}

std::size_t MetalFrameResources::dynamicHighWatermarkBytes() const
{
    return m_dynamicHighWatermark;
}

std::size_t MetalFrameResources::dynamicCapacityGrowthCount() const
{
    return m_dynamicCapacityGrowthCount;
}

std::size_t MetalFrameResources::lastRequiredCapacity() const
{
    return m_lastRequiredCapacity;
}

std::size_t MetalFrameResources::currentFrameAllocationCount() const
{
    return m_frames.empty() ? 0 : m_frames[m_currentFrameIndex].allocationCount;
}

std::size_t MetalFrameResources::totalDynamicAllocationCount() const
{
    return m_allocationSerial > std::numeric_limits<std::size_t>::max() ?
        std::numeric_limits<std::size_t>::max() :
        static_cast<std::size_t>(m_allocationSerial);
}

std::vector<MetalFrameResources::Allocation> MetalFrameResources::currentFrameAllocations() const
{
    return frameAllocations(m_currentFrameIndex);
}

std::vector<MetalFrameResources::Allocation> MetalFrameResources::frameAllocations(uint32_t frameIndex) const
{
    if (m_frames.empty()) {
        return {};
    }

    return m_frames[normalizeFrameIndex(frameIndex)].allocations;
}

bool MetalFrameResources::reserveDynamicCapacity(std::size_t requiredCapacity)
{
    const bool grewCapacity = ensureDynamicCapacity(requiredCapacity);
    m_lastDiagnostic = makeFrameDiagnostic(m_currentFrameIndex);
    return grewCapacity;
}

const MetalFrameResources::Allocation& MetalFrameResources::lastAllocation() const
{
    return m_lastAllocation;
}

MetalFrameResources::Diagnostics MetalFrameResources::diagnostics() const
{
    Diagnostics result;
    result.frameCount = frameCount();
    result.currentFrameIndex = m_currentFrameIndex;
    result.frameNumber = m_frameNumber;
    result.inFlightFrameCount = inFlightFrameCount();
    result.dynamicCapacity = m_dynamicCapacity;
    result.dynamicUsedBytes = dynamicUsedBytes();
    result.dynamicRemainingBytes = dynamicRemainingBytes();
    result.dynamicHighWatermarkBytes = m_dynamicHighWatermark;
    result.dynamicCapacityGrowthCount = m_dynamicCapacityGrowthCount;
    result.lastRequiredCapacity = m_lastRequiredCapacity;
    result.totalDynamicAllocationCount = totalDynamicAllocationCount();
    result.reusedSubmittedFrameCount = m_reusedSubmittedFrameCount;
    result.currentFrame = currentFrameMetadata();
    result.lastAllocation = m_lastAllocation;
    result.debugLabel = m_debugLabel;
    result.lastMessage = m_lastDiagnostic;
    return result;
}

const std::string& MetalFrameResources::lastDiagnostic() const
{
    return m_lastDiagnostic;
}

void MetalFrameResources::setDebugLabel(const char* label)
{
    m_debugLabel = label != nullptr ? label : std::string{};
    if (!m_frames.empty() && m_frames[m_currentFrameIndex].debugLabel.empty()) {
        m_frames[m_currentFrameIndex].debugLabel = m_debugLabel;
    }
    m_lastDiagnostic = makeFrameDiagnostic(m_currentFrameIndex);
}

const std::string& MetalFrameResources::debugLabel() const
{
    return m_debugLabel;
}

std::string MetalFrameResources::describeCurrentFrame() const
{
    return describeFrame(m_currentFrameIndex);
}

std::string MetalFrameResources::describeFrame(uint32_t frameIndex) const
{
    if (m_frames.empty()) {
        return "MetalFrameResources has no ring frames.";
    }

    return makeFrameDiagnostic(normalizeFrameIndex(frameIndex));
}

std::size_t MetalFrameResources::normalizeAlignment(std::size_t alignment)
{
    if (alignment <= 1) {
        return 1;
    }

    return alignment;
}

std::size_t MetalFrameResources::alignOffset(std::size_t offset, std::size_t alignment)
{
    const std::size_t normalizedAlignment = normalizeAlignment(alignment);
    if (normalizedAlignment == 1) {
        return offset;
    }

    const std::size_t remainder = offset % normalizedAlignment;
    if (remainder == 0) {
        return offset;
    }

    const std::size_t padding = normalizedAlignment - remainder;
    if (offset > std::numeric_limits<std::size_t>::max() - padding) {
        return std::numeric_limits<std::size_t>::max();
    }

    return offset + padding;
}

std::size_t MetalFrameResources::alignedSize(std::size_t size, std::size_t alignment)
{
    return alignOffset(size, alignment);
}

bool MetalFrameResources::isAligned(std::size_t offset, std::size_t alignment)
{
    const std::size_t normalizedAlignment = normalizeAlignment(alignment);
    return normalizedAlignment == 1 || offset % normalizedAlignment == 0;
}

const char* MetalFrameResources::framePhaseName(FramePhase phase)
{
    switch (phase) {
    case FramePhase::Available:
        return "available";
    case FramePhase::Encoding:
        return "encoding";
    case FramePhase::Submitted:
        return "submitted";
    case FramePhase::Completed:
        return "completed";
    }

    return "unknown";
}

bool MetalFrameResources::ensureDynamicCapacity(std::size_t requiredCapacity)
{
    m_lastRequiredCapacity = requiredCapacity;
    if (requiredCapacity <= m_dynamicCapacity) {
        return false;
    }

    m_dynamicCapacity = nextDynamicCapacity(requiredCapacity);
    ++m_dynamicCapacityGrowthCount;
    return true;
}

std::size_t MetalFrameResources::nextDynamicCapacity(std::size_t requiredCapacity) const
{
    if (requiredCapacity <= m_dynamicCapacity) {
        return m_dynamicCapacity;
    }

    std::size_t nextCapacity = std::max<std::size_t>(m_dynamicCapacity, kDefaultDynamicAlignment);
    while (nextCapacity < requiredCapacity) {
        if (nextCapacity > std::numeric_limits<std::size_t>::max() / 2) {
            return requiredCapacity;
        }
        nextCapacity *= 2;
    }
    return nextCapacity;
}

std::string MetalFrameResources::makeFrameDiagnostic(uint32_t frameIndex) const
{
    if (m_frames.empty()) {
        return "MetalFrameResources has no ring frames.";
    }

    const uint32_t normalizedFrameIndex =
        static_cast<uint32_t>(frameIndex % static_cast<uint32_t>(m_frames.size()));
    const FrameState& frame = m_frames[normalizedFrameIndex];

    std::ostringstream stream;
    stream << m_debugLabel
           << " frameIndex=" << normalizedFrameIndex
           << "/" << m_frames.size()
           << " current=" << (frame.isCurrent ? "yes" : "no")
           << " phase=" << framePhaseName(frame.phase)
           << " inFlight=" << (frame.phase == FramePhase::Submitted ? "yes" : "no")
           << " frameNumber=" << frame.frameNumber
           << " globalFrameNumber=" << m_frameNumber
           << " dynamicOffset=" << frame.dynamicOffset
           << " dynamicCapacity=" << m_dynamicCapacity
           << " dynamicRemaining=" << (frame.dynamicOffset <= m_dynamicCapacity ? m_dynamicCapacity - frame.dynamicOffset : 0)
           << " allocationCount=" << frame.allocationCount
           << " allocationLedgerCount=" << frame.allocations.size()
           << " frameHighWatermark=" << frame.highWatermark
           << " ringHighWatermark=" << m_dynamicHighWatermark
           << " capacityGrowths=" << m_dynamicCapacityGrowthCount
           << " lastRequiredCapacity=" << m_lastRequiredCapacity
           << " reusedSubmittedFrames=" << m_reusedSubmittedFrameCount
           << " submissionSerial=" << frame.submissionSerial
           << " completionSerial=" << frame.completionSerial;

    if (!frame.debugLabel.empty()) {
        stream << " frameLabel='" << frame.debugLabel << "'";
    }

    if (m_lastAllocation.isValid() && m_lastAllocation.frameIndex == normalizedFrameIndex) {
        stream << " lastAllocationOffset=" << m_lastAllocation.offset
               << " lastAllocationSize=" << m_lastAllocation.size
               << " lastAllocationAlignment=" << m_lastAllocation.alignment
               << " lastAllocationPadding=" << m_lastAllocation.padding
               << " lastAllocationSerial=" << m_lastAllocation.allocationSerial
               << " lastAllocationGrewCapacity=" << (m_lastAllocation.grewCapacity ? "yes" : "no");
        if (!m_lastAllocation.debugLabel.empty()) {
            stream << " lastAllocationLabel='" << m_lastAllocation.debugLabel << "'";
        }
    }

    return stream.str();
}

} // namespace mesh2splat::metal
