#pragma once

#include "MetalRenderTarget.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace mesh2splat::metal {

using MetalRenderTargetPoolSlotIndex = uint32_t;

inline constexpr MetalRenderTargetPoolSlotIndex kInvalidMetalRenderTargetPoolSlotIndex =
    std::numeric_limits<MetalRenderTargetPoolSlotIndex>::max();

enum class MetalRenderTargetReuseMode : uint8_t {
    Exact,
    CompatibleSize,
    Dedicated,
};

enum class MetalRenderTargetPoolSlotState : uint8_t {
    Empty,
    Available,
    Acquired,
};

enum class MetalRenderTargetPoolAcquireAction : uint8_t {
    Failed,
    ReusedExistingTarget,
    CreatedNewTarget,
};

enum class MetalRenderTargetPoolReleaseAction : uint8_t {
    Failed,
    ReturnedToPool,
    DiscardedTarget,
};

enum class MetalRenderTargetPoolDiscardAction : uint8_t {
    Failed,
    DiscardedTarget,
};

enum class MetalRenderTargetPoolResetMode : uint8_t {
    ClearTargets,
    ResetPool,
};

enum class MetalRenderTargetPoolResetAction : uint8_t {
    ClearedTargets,
    ResetPool,
};

struct MetalRenderTargetReusePolicy {
    MetalRenderTargetReuseMode mode = MetalRenderTargetReuseMode::Exact;
    uint32_t maxIdleFrames = 3;
    bool allowRoleMismatch = false;

    bool isReusable() const
    {
        return mode != MetalRenderTargetReuseMode::Dedicated;
    }

    bool isDedicated() const
    {
        return mode == MetalRenderTargetReuseMode::Dedicated;
    }
};

struct MetalRenderTargetPoolHandle {
    MetalRenderTargetPoolSlotIndex slotIndex = kInvalidMetalRenderTargetPoolSlotIndex;
    uint32_t generation = 0;

    bool isValid() const
    {
        return slotIndex != kInvalidMetalRenderTargetPoolSlotIndex && generation != 0;
    }
};

inline bool operator==(const MetalRenderTargetPoolHandle& lhs, const MetalRenderTargetPoolHandle& rhs)
{
    return lhs.slotIndex == rhs.slotIndex && lhs.generation == rhs.generation;
}

inline bool operator!=(const MetalRenderTargetPoolHandle& lhs, const MetalRenderTargetPoolHandle& rhs)
{
    return !(lhs == rhs);
}

struct MetalRenderTargetPoolKey {
    MetalRenderTargetRole role = MetalRenderTargetRole::Unknown;
    MetalRenderTargetSize size{};
    bool colorEnabled = true;
    bool depthEnabled = false;
    MetalTextureFormat colorFormat = MetalTextureFormat::BGRA8Unorm;
    MetalTextureFormat depthFormat = MetalTextureFormat::Depth32Float;

    bool isValid() const
    {
        return size.width != 0 && size.height != 0 && (colorEnabled || depthEnabled);
    }

    bool hasSameAttachmentsAndFormats(const MetalRenderTargetPoolKey& other) const
    {
        return colorEnabled == other.colorEnabled &&
            depthEnabled == other.depthEnabled &&
            (!colorEnabled || colorFormat == other.colorFormat) &&
            (!depthEnabled || depthFormat == other.depthFormat);
    }

    bool hasExactSize(const MetalRenderTargetPoolKey& other) const
    {
        return size.width == other.size.width && size.height == other.size.height;
    }

    bool canContainSize(const MetalRenderTargetPoolKey& other) const
    {
        return size.width >= other.size.width && size.height >= other.size.height;
    }
};

inline bool operator==(const MetalRenderTargetPoolKey& lhs, const MetalRenderTargetPoolKey& rhs)
{
    return lhs.role == rhs.role &&
        lhs.size.width == rhs.size.width &&
        lhs.size.height == rhs.size.height &&
        lhs.colorEnabled == rhs.colorEnabled &&
        lhs.depthEnabled == rhs.depthEnabled &&
        (!lhs.colorEnabled || lhs.colorFormat == rhs.colorFormat) &&
        (!lhs.depthEnabled || lhs.depthFormat == rhs.depthFormat);
}

inline bool operator!=(const MetalRenderTargetPoolKey& lhs, const MetalRenderTargetPoolKey& rhs)
{
    return !(lhs == rhs);
}

struct MetalRenderTargetPoolMemoryEstimate {
    MetalRenderTargetPoolKey key;
    bool valid = false;
    bool overflowed = false;
    std::size_t colorSizeBytes = 0;
    std::size_t depthSizeBytes = 0;
    std::size_t totalSizeBytes = 0;
};

struct MetalRenderTargetPoolAcquireDesc {
    MetalRenderTargetPoolKey key;
    MetalRenderTargetReusePolicy reusePolicy;
    bool useDefaultReusePolicy = true;
    uint64_t frameNumber = 0;
    MetalClearColor clearColor{};
    double clearDepth = 1.0;
    std::string debugLabel;

    bool isValid() const
    {
        return key.isValid();
    }
};

struct MetalRenderTargetPoolReleaseDesc {
    MetalRenderTargetPoolHandle handle;
    uint64_t frameNumber = 0;

    bool isValid() const
    {
        return handle.isValid();
    }
};

struct MetalRenderTargetPoolDiscardDesc {
    MetalRenderTargetPoolHandle handle;

    bool isValid() const
    {
        return handle.isValid();
    }
};

struct MetalRenderTargetPoolPruneDesc {
    uint64_t currentFrameNumber = 0;
};

struct MetalRenderTargetPoolResetDesc {
    MetalRenderTargetPoolResetMode mode = MetalRenderTargetPoolResetMode::ClearTargets;
    bool resetDiagnostics = false;
};

struct MetalRenderTargetPoolEntry {
    MetalRenderTargetPoolHandle handle;
    MetalRenderTargetPoolSlotState state = MetalRenderTargetPoolSlotState::Empty;
    MetalRenderTargetPoolKey key;
    MetalRenderTargetReusePolicy reusePolicy;
    uint64_t createFrame = 0;
    uint64_t lastAcquireFrame = 0;
    uint64_t lastReleaseFrame = 0;
    std::size_t acquireCount = 0;
    MetalClearColor clearColor{};
    double clearDepth = 1.0;
    std::string debugLabel;

    bool isEmpty() const
    {
        return state == MetalRenderTargetPoolSlotState::Empty;
    }

    bool isAvailable() const
    {
        return state == MetalRenderTargetPoolSlotState::Available;
    }

    bool isAcquired() const
    {
        return state == MetalRenderTargetPoolSlotState::Acquired;
    }
};

struct MetalRenderTargetPoolSlotSnapshot {
    MetalRenderTargetPoolHandle handle;
    MetalRenderTargetPoolSlotState state = MetalRenderTargetPoolSlotState::Empty;
    MetalRenderTargetPoolKey key;
    MetalRenderTargetReusePolicy reusePolicy;
    MetalRenderTargetPoolMemoryEstimate memoryEstimate;
    MetalRenderTargetDesc descriptor;
    uint64_t createFrame = 0;
    uint64_t lastAcquireFrame = 0;
    uint64_t lastReleaseFrame = 0;
    std::size_t acquireCount = 0;
    MetalClearColor clearColor{};
    double clearDepth = 1.0;
    std::string debugLabel;

    bool hasTarget() const
    {
        return handle.isValid() && state != MetalRenderTargetPoolSlotState::Empty;
    }
};

struct MetalRenderTargetPoolEntryDiagnostics {
    MetalRenderTargetPoolHandle handle;
    MetalRenderTargetPoolSlotState state = MetalRenderTargetPoolSlotState::Empty;
    MetalRenderTargetPoolKey key;
    MetalRenderTargetReusePolicy reusePolicy;
    MetalRenderTargetPoolMemoryEstimate memoryEstimate;
    MetalRenderTargetDesc descriptor;
    uint64_t createFrame = 0;
    uint64_t lastAcquireFrame = 0;
    uint64_t lastReleaseFrame = 0;
    std::size_t acquireCount = 0;
    MetalClearColor clearColor{};
    double clearDepth = 1.0;
    std::string debugLabel;
    std::string stateName;
    std::string reuseModeName;
    std::string keyString;
};

struct MetalRenderTargetPoolAcquireResult {
    bool success = false;
    MetalRenderTargetPoolAcquireAction action = MetalRenderTargetPoolAcquireAction::Failed;
    MetalRenderTargetPoolHandle handle;
    MetalRenderTargetPoolKey requestedKey;
    MetalRenderTargetReusePolicy reusePolicy;
    MetalRenderTargetDesc descriptor;
    MetalRenderTargetPoolMemoryEstimate requestedMemoryEstimate;
    MetalRenderTargetPoolMemoryEstimate memoryEstimate;
    MetalRenderTargetPoolSlotSnapshot slot;
    uint64_t frameNumber = 0;
    std::string diagnostic;

    bool didReuseTarget() const
    {
        return success && action == MetalRenderTargetPoolAcquireAction::ReusedExistingTarget;
    }

    bool needsTargetCreation() const
    {
        return success && action == MetalRenderTargetPoolAcquireAction::CreatedNewTarget;
    }
};

struct MetalRenderTargetPoolReleaseResult {
    bool success = false;
    MetalRenderTargetPoolReleaseAction action = MetalRenderTargetPoolReleaseAction::Failed;
    MetalRenderTargetPoolHandle handle;
    MetalRenderTargetPoolSlotSnapshot slot;
    uint64_t frameNumber = 0;
    std::string diagnostic;

    bool returnedToPool() const
    {
        return success && action == MetalRenderTargetPoolReleaseAction::ReturnedToPool;
    }

    bool shouldDestroyTarget() const
    {
        return success && action == MetalRenderTargetPoolReleaseAction::DiscardedTarget;
    }
};

struct MetalRenderTargetPoolDiscardResult {
    bool success = false;
    MetalRenderTargetPoolDiscardAction action = MetalRenderTargetPoolDiscardAction::Failed;
    MetalRenderTargetPoolHandle handle;
    MetalRenderTargetPoolSlotSnapshot slot;
    std::string diagnostic;

    bool shouldDestroyTarget() const
    {
        return success && action == MetalRenderTargetPoolDiscardAction::DiscardedTarget;
    }
};

struct MetalRenderTargetPoolPruneResult {
    bool success = true;
    uint64_t frameNumber = 0;
    std::size_t prunedCount = 0;
    std::vector<MetalRenderTargetPoolSlotSnapshot> discardedSlots;
    std::string diagnostic;

    bool hasDiscardedTargets() const
    {
        return !discardedSlots.empty();
    }
};

struct MetalRenderTargetPoolResetResult {
    bool success = true;
    MetalRenderTargetPoolResetAction action = MetalRenderTargetPoolResetAction::ClearedTargets;
    std::size_t discardedCount = 0;
    std::vector<MetalRenderTargetPoolSlotSnapshot> discardedSlots;
    std::string diagnostic;

    bool hasDiscardedTargets() const
    {
        return !discardedSlots.empty();
    }
};

struct MetalRenderTargetPoolDiagnostics {
    std::size_t slotCount = 0;
    std::size_t availableCount = 0;
    std::size_t acquiredCount = 0;
    std::size_t emptyCount = 0;
    std::size_t acquireCount = 0;
    std::size_t releaseCount = 0;
    std::size_t hitCount = 0;
    std::size_t missCount = 0;
    std::size_t discardCount = 0;
    std::size_t pruneCount = 0;
    std::size_t estimatedBytes = 0;
    std::size_t availableEstimatedBytes = 0;
    std::size_t acquiredEstimatedBytes = 0;
    std::size_t reclaimableEstimatedBytes = 0;
    bool memoryEstimateOverflowed = false;
    MetalRenderTargetReusePolicy defaultReusePolicy;
    std::string lastEvent;
    std::vector<MetalRenderTargetPoolEntryDiagnostics> entries;
};

namespace detail {

inline bool addPoolSize(std::size_t lhs, std::size_t rhs, std::size_t& result)
{
    if (lhs > std::numeric_limits<std::size_t>::max() - rhs) {
        result = 0;
        return false;
    }

    result = lhs + rhs;
    return true;
}

inline bool multiplyPoolSize(std::size_t lhs, std::size_t rhs, std::size_t& result)
{
    if (lhs != 0 && rhs > std::numeric_limits<std::size_t>::max() / lhs) {
        result = 0;
        return false;
    }

    result = lhs * rhs;
    return true;
}

inline uint32_t nextPoolGeneration(uint32_t generation)
{
    uint32_t nextGeneration = generation + 1;
    if (nextGeneration == 0) {
        nextGeneration = 1;
    }
    return nextGeneration;
}

} // namespace detail

class MetalRenderTargetPool {
public:
    explicit MetalRenderTargetPool(MetalRenderTargetReusePolicy defaultReusePolicy = {})
        : m_defaultReusePolicy(defaultReusePolicy)
    {
    }

    MetalRenderTargetPoolHandle acquire(
        const MetalRenderTargetDesc& desc,
        uint64_t frameNumber = 0,
        const char* debugLabel = nullptr)
    {
        return acquireTarget(desc, frameNumber, debugLabel).handle;
    }

    MetalRenderTargetPoolHandle acquire(
        const MetalRenderTargetDesc& desc,
        const MetalRenderTargetReusePolicy& reusePolicy,
        uint64_t frameNumber = 0,
        const char* debugLabel = nullptr)
    {
        return acquireTarget(desc, reusePolicy, frameNumber, debugLabel).handle;
    }

    MetalRenderTargetPoolHandle acquire(
        const MetalRenderTargetPoolKey& key,
        uint64_t frameNumber = 0,
        const char* debugLabel = nullptr)
    {
        return acquireTarget(key, frameNumber, debugLabel).handle;
    }

    MetalRenderTargetPoolHandle acquire(
        const MetalRenderTargetPoolKey& key,
        const MetalRenderTargetReusePolicy& reusePolicy,
        uint64_t frameNumber = 0,
        const char* debugLabel = nullptr)
    {
        return acquireTarget(key, reusePolicy, frameNumber, debugLabel).handle;
    }

    MetalRenderTargetPoolAcquireResult acquireTarget(
        const MetalRenderTargetDesc& desc,
        uint64_t frameNumber = 0,
        const char* debugLabel = nullptr)
    {
        MetalRenderTargetPoolAcquireDesc acquireDesc;
        acquireDesc.key = makeKey(desc);
        acquireDesc.frameNumber = frameNumber;
        acquireDesc.clearColor = desc.clearColor;
        acquireDesc.clearDepth = desc.clearDepth;
        acquireDesc.debugLabel = labelForDesc(desc, debugLabel);
        return acquireTarget(acquireDesc);
    }

    MetalRenderTargetPoolAcquireResult acquireTarget(
        const MetalRenderTargetDesc& desc,
        const MetalRenderTargetReusePolicy& reusePolicy,
        uint64_t frameNumber = 0,
        const char* debugLabel = nullptr)
    {
        MetalRenderTargetPoolAcquireDesc acquireDesc;
        acquireDesc.key = makeKey(desc);
        acquireDesc.reusePolicy = reusePolicy;
        acquireDesc.useDefaultReusePolicy = false;
        acquireDesc.frameNumber = frameNumber;
        acquireDesc.clearColor = desc.clearColor;
        acquireDesc.clearDepth = desc.clearDepth;
        acquireDesc.debugLabel = labelForDesc(desc, debugLabel);
        return acquireTarget(acquireDesc);
    }

    MetalRenderTargetPoolAcquireResult acquireTarget(
        const MetalRenderTargetPoolKey& key,
        uint64_t frameNumber = 0,
        const char* debugLabel = nullptr)
    {
        MetalRenderTargetPoolAcquireDesc acquireDesc;
        acquireDesc.key = key;
        acquireDesc.frameNumber = frameNumber;
        acquireDesc.debugLabel = labelString(debugLabel);
        return acquireTarget(acquireDesc);
    }

    MetalRenderTargetPoolAcquireResult acquireTarget(
        const MetalRenderTargetPoolKey& key,
        const MetalRenderTargetReusePolicy& reusePolicy,
        uint64_t frameNumber = 0,
        const char* debugLabel = nullptr)
    {
        MetalRenderTargetPoolAcquireDesc acquireDesc;
        acquireDesc.key = key;
        acquireDesc.reusePolicy = reusePolicy;
        acquireDesc.useDefaultReusePolicy = false;
        acquireDesc.frameNumber = frameNumber;
        acquireDesc.debugLabel = labelString(debugLabel);
        return acquireTarget(acquireDesc);
    }

    MetalRenderTargetPoolAcquireResult acquireTarget(const MetalRenderTargetPoolAcquireDesc& desc)
    {
        return acquire(desc);
    }

    bool release(MetalRenderTargetPoolHandle handle, uint64_t frameNumber = 0)
    {
        return releaseTarget(handle, frameNumber).success;
    }

    MetalRenderTargetPoolReleaseResult releaseTarget(
        MetalRenderTargetPoolHandle handle,
        uint64_t frameNumber = 0)
    {
        MetalRenderTargetPoolReleaseDesc desc;
        desc.handle = handle;
        desc.frameNumber = frameNumber;
        return releaseTarget(desc);
    }

    MetalRenderTargetPoolReleaseResult releaseTarget(const MetalRenderTargetPoolReleaseDesc& desc)
    {
        return release(desc);
    }

    bool discard(MetalRenderTargetPoolHandle handle)
    {
        return discardTarget(handle).success;
    }

    MetalRenderTargetPoolDiscardResult discardTarget(MetalRenderTargetPoolHandle handle)
    {
        MetalRenderTargetPoolDiscardDesc desc;
        desc.handle = handle;
        return discardTarget(desc);
    }

    MetalRenderTargetPoolDiscardResult discardTarget(const MetalRenderTargetPoolDiscardDesc& desc)
    {
        return discard(desc);
    }

    std::size_t pruneIdle(uint64_t currentFrameNumber)
    {
        return pruneIdleTargets(currentFrameNumber).prunedCount;
    }

    MetalRenderTargetPoolPruneResult pruneIdleTargets(uint64_t currentFrameNumber)
    {
        MetalRenderTargetPoolPruneDesc desc;
        desc.currentFrameNumber = currentFrameNumber;
        return pruneIdleTargets(desc);
    }

    MetalRenderTargetPoolPruneResult pruneIdleTargets(const MetalRenderTargetPoolPruneDesc& desc)
    {
        return pruneIdle(desc);
    }

    void clear()
    {
        (void)clearTargets();
    }

    MetalRenderTargetPoolResetResult clearTargets()
    {
        MetalRenderTargetPoolResetDesc desc;
        desc.mode = MetalRenderTargetPoolResetMode::ClearTargets;
        return resetTargets(desc);
    }

    void reset()
    {
        (void)resetPool();
    }

    MetalRenderTargetPoolResetResult resetPool(bool resetCounters = true)
    {
        MetalRenderTargetPoolResetDesc desc;
        desc.mode = MetalRenderTargetPoolResetMode::ResetPool;
        desc.resetDiagnostics = resetCounters;
        return resetTargets(desc);
    }

    MetalRenderTargetPoolResetResult resetTargets(const MetalRenderTargetPoolResetDesc& desc)
    {
        return reset(desc);
    }

    void resetDiagnostics()
    {
        m_acquireCount = 0;
        m_releaseCount = 0;
        m_hitCount = 0;
        m_missCount = 0;
        m_discardCount = 0;
        m_pruneCount = 0;
        m_lastEvent.clear();
    }

    bool contains(MetalRenderTargetPoolHandle handle) const
    {
        return entry(handle) != nullptr;
    }

    bool isAvailable(MetalRenderTargetPoolHandle handle) const
    {
        const MetalRenderTargetPoolEntry* targetEntry = entry(handle);
        return targetEntry != nullptr && targetEntry->isAvailable();
    }

    bool isAcquired(MetalRenderTargetPoolHandle handle) const
    {
        const MetalRenderTargetPoolEntry* targetEntry = entry(handle);
        return targetEntry != nullptr && targetEntry->isAcquired();
    }

    const MetalRenderTargetPoolEntry* entry(MetalRenderTargetPoolHandle handle) const
    {
        if (!handle.isValid() || handle.slotIndex >= m_entries.size()) {
            return nullptr;
        }

        const MetalRenderTargetPoolEntry& targetEntry = m_entries[handle.slotIndex];
        if (targetEntry.isEmpty() || targetEntry.handle.generation != handle.generation) {
            return nullptr;
        }

        return &targetEntry;
    }

    std::size_t slotCount() const
    {
        return m_entries.size();
    }

    std::size_t liveSlotCount() const
    {
        return countSlots(MetalRenderTargetPoolSlotState::Available) +
            countSlots(MetalRenderTargetPoolSlotState::Acquired);
    }

    std::size_t availableCount() const
    {
        return countSlots(MetalRenderTargetPoolSlotState::Available);
    }

    std::size_t acquiredCount() const
    {
        return countSlots(MetalRenderTargetPoolSlotState::Acquired);
    }

    std::size_t emptyCount() const
    {
        return countSlots(MetalRenderTargetPoolSlotState::Empty);
    }

    std::size_t estimatedBytes() const
    {
        return diagnostics(false).estimatedBytes;
    }

    MetalRenderTargetPoolEntryDiagnostics entryDiagnostics(MetalRenderTargetPoolHandle handle) const
    {
        const MetalRenderTargetPoolEntry* targetEntry = entry(handle);
        return targetEntry == nullptr ? MetalRenderTargetPoolEntryDiagnostics{} : makeEntryDiagnostics(*targetEntry);
    }

    MetalRenderTargetPoolSlotSnapshot slotSnapshot(MetalRenderTargetPoolHandle handle) const
    {
        const MetalRenderTargetPoolEntry* targetEntry = entry(handle);
        return targetEntry == nullptr ? MetalRenderTargetPoolSlotSnapshot{} : makeSlotSnapshot(*targetEntry);
    }

    MetalRenderTargetPoolDiagnostics diagnostics(bool includeEntries = true) const
    {
        MetalRenderTargetPoolDiagnostics result;
        result.slotCount = m_entries.size();
        result.acquireCount = m_acquireCount;
        result.releaseCount = m_releaseCount;
        result.hitCount = m_hitCount;
        result.missCount = m_missCount;
        result.discardCount = m_discardCount;
        result.pruneCount = m_pruneCount;
        result.defaultReusePolicy = m_defaultReusePolicy;
        result.lastEvent = m_lastEvent;

        if (includeEntries) {
            result.entries.reserve(m_entries.size());
        }

        for (const MetalRenderTargetPoolEntry& targetEntry : m_entries) {
            switch (targetEntry.state) {
            case MetalRenderTargetPoolSlotState::Empty:
                ++result.emptyCount;
                break;
            case MetalRenderTargetPoolSlotState::Available:
                ++result.availableCount;
                break;
            case MetalRenderTargetPoolSlotState::Acquired:
                ++result.acquiredCount;
                break;
            }

            if (targetEntry.isEmpty()) {
                if (includeEntries) {
                    result.entries.push_back(makeEntryDiagnostics(targetEntry));
                }
                continue;
            }

            const MetalRenderTargetPoolMemoryEstimate estimate = estimateMemory(targetEntry.key);
            result.memoryEstimateOverflowed = result.memoryEstimateOverflowed || estimate.overflowed;

            std::size_t nextEstimatedBytes = 0;
            if (!detail::addPoolSize(result.estimatedBytes, estimate.totalSizeBytes, nextEstimatedBytes)) {
                result.memoryEstimateOverflowed = true;
            } else {
                result.estimatedBytes = nextEstimatedBytes;
            }

            if (targetEntry.isAvailable()) {
                addEstimateToTotal(estimate, result.availableEstimatedBytes, result.memoryEstimateOverflowed);
                addEstimateToTotal(estimate, result.reclaimableEstimatedBytes, result.memoryEstimateOverflowed);
            } else if (targetEntry.isAcquired()) {
                addEstimateToTotal(estimate, result.acquiredEstimatedBytes, result.memoryEstimateOverflowed);
            }

            if (includeEntries) {
                result.entries.push_back(makeEntryDiagnostics(targetEntry));
            }
        }

        return result;
    }

    const std::string& lastDiagnostic() const
    {
        return m_lastEvent;
    }

    const MetalRenderTargetReusePolicy& defaultReusePolicy() const
    {
        return m_defaultReusePolicy;
    }

    void setDefaultReusePolicy(MetalRenderTargetReusePolicy reusePolicy)
    {
        m_defaultReusePolicy = reusePolicy;
    }

    static MetalRenderTargetPoolKey makeKey(const MetalRenderTargetDesc& desc)
    {
        MetalRenderTargetPoolKey key;
        key.role = desc.role;
        key.size = { desc.width, desc.height };
        key.colorEnabled = desc.colorEnabled;
        key.depthEnabled = desc.depthEnabled;
        key.colorFormat = desc.colorFormat;
        key.depthFormat = desc.depthFormat;
        return key;
    }

    static MetalRenderTargetDesc makeDescriptor(
        const MetalRenderTargetPoolKey& key,
        const char* debugLabel = nullptr,
        MetalClearColor clearColor = MetalClearColor{},
        double clearDepth = 1.0)
    {
        MetalRenderTargetDesc desc;
        desc.width = key.size.width;
        desc.height = key.size.height;
        desc.colorEnabled = key.colorEnabled;
        desc.depthEnabled = key.depthEnabled;
        desc.colorFormat = key.colorFormat;
        desc.depthFormat = key.depthFormat;
        desc.clearColor = clearColor;
        desc.clearDepth = clearDepth;
        desc.role = key.role;
        desc.label = labelString(debugLabel);
        return desc;
    }

    static bool canReuse(
        const MetalRenderTargetPoolKey& candidate,
        const MetalRenderTargetPoolKey& requested,
        const MetalRenderTargetReusePolicy& reusePolicy)
    {
        if (!candidate.isValid() || !requested.isValid() || !reusePolicy.isReusable()) {
            return false;
        }
        if (!candidate.hasSameAttachmentsAndFormats(requested)) {
            return false;
        }
        if (!reusePolicy.allowRoleMismatch && candidate.role != requested.role) {
            return false;
        }

        switch (reusePolicy.mode) {
        case MetalRenderTargetReuseMode::Exact:
            return candidate.hasExactSize(requested);
        case MetalRenderTargetReuseMode::CompatibleSize:
            return candidate.canContainSize(requested);
        case MetalRenderTargetReuseMode::Dedicated:
            return false;
        }

        return false;
    }

    static MetalRenderTargetPoolMemoryEstimate estimateMemory(const MetalRenderTargetPoolKey& key)
    {
        MetalRenderTargetPoolMemoryEstimate estimate;
        estimate.key = key;

        if (!key.isValid()) {
            return estimate;
        }

        std::size_t pixelCount = 0;
        estimate.overflowed = !detail::multiplyPoolSize(
            static_cast<std::size_t>(key.size.width),
            static_cast<std::size_t>(key.size.height),
            pixelCount);
        if (estimate.overflowed) {
            return estimate;
        }

        if (key.colorEnabled &&
            !attachmentSizeBytes(pixelCount, key.colorFormat, estimate.colorSizeBytes)) {
            estimate.overflowed = true;
            return estimate;
        }

        if (key.depthEnabled &&
            !attachmentSizeBytes(pixelCount, key.depthFormat, estimate.depthSizeBytes)) {
            estimate.overflowed = true;
            return estimate;
        }

        estimate.overflowed = !detail::addPoolSize(
            estimate.colorSizeBytes,
            estimate.depthSizeBytes,
            estimate.totalSizeBytes);
        estimate.valid = !estimate.overflowed;
        return estimate;
    }

    static MetalRenderTargetPoolMemoryEstimate estimateMemory(const MetalRenderTargetDesc& desc)
    {
        return estimateMemory(makeKey(desc));
    }

    static MetalRenderTargetPoolMemoryEstimate estimateMemory(const MetalRenderTarget& target)
    {
        MetalRenderTargetPoolMemoryEstimate estimate;
        estimate.key = makeKey(target.descriptor());
        estimate.valid = target.isValid();
        estimate.colorSizeBytes = target.colorSizeBytes();
        estimate.depthSizeBytes = target.depthSizeBytes();
        estimate.totalSizeBytes = target.sizeBytes();
        estimate.overflowed = estimate.valid && estimate.totalSizeBytes == 0;
        return estimate;
    }

    static const char* reuseModeName(MetalRenderTargetReuseMode mode)
    {
        switch (mode) {
        case MetalRenderTargetReuseMode::Exact:
            return "Exact";
        case MetalRenderTargetReuseMode::CompatibleSize:
            return "CompatibleSize";
        case MetalRenderTargetReuseMode::Dedicated:
            return "Dedicated";
        }

        return "Unknown";
    }

    static const char* slotStateName(MetalRenderTargetPoolSlotState state)
    {
        switch (state) {
        case MetalRenderTargetPoolSlotState::Empty:
            return "Empty";
        case MetalRenderTargetPoolSlotState::Available:
            return "Available";
        case MetalRenderTargetPoolSlotState::Acquired:
            return "Acquired";
        }

        return "Unknown";
    }

    static const char* roleName(MetalRenderTargetRole role)
    {
        switch (role) {
        case MetalRenderTargetRole::Unknown:
            return "Unknown";
        case MetalRenderTargetRole::Main:
            return "Main";
        case MetalRenderTargetRole::Depth:
            return "Depth";
        case MetalRenderTargetRole::Offscreen:
            return "Offscreen";
        }

        return "Unknown";
    }

    static const char* formatName(MetalTextureFormat format)
    {
        switch (format) {
        case MetalTextureFormat::BGRA8Unorm:
            return "BGRA8Unorm";
        case MetalTextureFormat::BGRA8UnormSrgb:
            return "BGRA8UnormSrgb";
        case MetalTextureFormat::RGBA8Unorm:
            return "RGBA8Unorm";
        case MetalTextureFormat::RGBA8UnormSrgb:
            return "RGBA8UnormSrgb";
        case MetalTextureFormat::R8Unorm:
            return "R8Unorm";
        case MetalTextureFormat::Depth32Float:
            return "Depth32Float";
        }

        return "Unknown";
    }

    static std::string keyString(const MetalRenderTargetPoolKey& key)
    {
        std::ostringstream stream;
        stream << "role=" << roleName(key.role)
            << "|size=" << key.size.width << "x" << key.size.height
            << "|color=" << (key.colorEnabled ? formatName(key.colorFormat) : "None")
            << "|depth=" << (key.depthEnabled ? formatName(key.depthFormat) : "None");
        return stream.str();
    }

    static std::string handleDescription(MetalRenderTargetPoolHandle handle)
    {
        std::ostringstream stream;
        stream << "#" << handle.slotIndex << ":" << handle.generation;
        return stream.str();
    }

private:
    MetalRenderTargetPoolAcquireResult acquire(const MetalRenderTargetPoolAcquireDesc& desc)
    {
        ++m_acquireCount;

        MetalRenderTargetPoolAcquireResult result;
        result.requestedKey = desc.key;
        result.reusePolicy = desc.useDefaultReusePolicy ? m_defaultReusePolicy : desc.reusePolicy;
        result.descriptor = makeDescriptor(desc.key, desc.debugLabel.c_str(), desc.clearColor, desc.clearDepth);
        result.requestedMemoryEstimate = estimateMemory(desc.key);
        result.memoryEstimate = result.requestedMemoryEstimate;
        result.frameNumber = desc.frameNumber;

        if (!result.requestedMemoryEstimate.valid) {
            ++m_missCount;
            m_lastEvent = "Metal render target pool acquire failed: invalid key " + keyString(desc.key) + ".";
            result.diagnostic = m_lastEvent;
            return result;
        }

        MetalRenderTargetPoolSlotIndex slotIndex = findReusableSlot(desc.key, result.reusePolicy);
        if (slotIndex != kInvalidMetalRenderTargetPoolSlotIndex) {
            MetalRenderTargetPoolEntry& targetEntry = m_entries[slotIndex];
            ++m_hitCount;
            targetEntry.state = MetalRenderTargetPoolSlotState::Acquired;
            targetEntry.reusePolicy = result.reusePolicy;
            targetEntry.lastAcquireFrame = desc.frameNumber;
            targetEntry.clearColor = desc.clearColor;
            targetEntry.clearDepth = desc.clearDepth;
            ++targetEntry.acquireCount;
            if (!desc.debugLabel.empty()) {
                targetEntry.debugLabel = desc.debugLabel;
            }
            m_lastEvent = "Metal render target pool hit slot " +
                handleDescription(targetEntry.handle) + " for " + keyString(desc.key) + ".";
            result.success = true;
            result.action = MetalRenderTargetPoolAcquireAction::ReusedExistingTarget;
            result.handle = targetEntry.handle;
            result.slot = makeSlotSnapshot(targetEntry);
            result.descriptor = result.slot.descriptor;
            result.memoryEstimate = result.slot.memoryEstimate;
            result.diagnostic = m_lastEvent;
            return result;
        }

        ++m_missCount;
        MetalRenderTargetPoolEntry* targetEntry = allocateSlot();
        if (targetEntry == nullptr) {
            m_lastEvent = "Metal render target pool acquire failed: slot index capacity was exhausted.";
            result.diagnostic = m_lastEvent;
            return result;
        }

        targetEntry->state = MetalRenderTargetPoolSlotState::Acquired;
        targetEntry->key = desc.key;
        targetEntry->reusePolicy = result.reusePolicy;
        targetEntry->createFrame = desc.frameNumber;
        targetEntry->lastAcquireFrame = desc.frameNumber;
        targetEntry->lastReleaseFrame = 0;
        targetEntry->acquireCount = 1;
        targetEntry->clearColor = desc.clearColor;
        targetEntry->clearDepth = desc.clearDepth;
        targetEntry->debugLabel = desc.debugLabel.empty() ? keyString(desc.key) : desc.debugLabel;
        m_lastEvent = "Metal render target pool miss allocated slot " +
            handleDescription(targetEntry->handle) + " for " + keyString(desc.key) + ".";
        result.success = true;
        result.action = MetalRenderTargetPoolAcquireAction::CreatedNewTarget;
        result.handle = targetEntry->handle;
        result.slot = makeSlotSnapshot(*targetEntry);
        result.descriptor = result.slot.descriptor;
        result.memoryEstimate = result.slot.memoryEstimate;
        result.diagnostic = m_lastEvent;
        return result;
    }

    MetalRenderTargetPoolReleaseResult release(const MetalRenderTargetPoolReleaseDesc& desc)
    {
        MetalRenderTargetPoolReleaseResult result;
        result.handle = desc.handle;
        result.frameNumber = desc.frameNumber;

        MetalRenderTargetPoolEntry* targetEntry = mutableEntry(desc.handle);
        if (targetEntry == nullptr) {
            m_lastEvent = "Metal render target pool release failed: handle is invalid.";
            result.diagnostic = m_lastEvent;
            return result;
        }
        if (!targetEntry->isAcquired()) {
            m_lastEvent = "Metal render target pool release failed: slot is not acquired.";
            result.slot = makeSlotSnapshot(*targetEntry);
            result.diagnostic = m_lastEvent;
            return result;
        }

        ++m_releaseCount;
        targetEntry->lastReleaseFrame = desc.frameNumber;
        if (targetEntry->reusePolicy.isDedicated()) {
            result.slot = makeSlotSnapshot(*targetEntry);
            discardEntry(*targetEntry);
            m_lastEvent = "Metal render target pool released and discarded dedicated slot " +
                handleDescription(desc.handle) + ".";
            result.success = true;
            result.action = MetalRenderTargetPoolReleaseAction::DiscardedTarget;
            result.diagnostic = m_lastEvent;
            return result;
        }

        targetEntry->state = MetalRenderTargetPoolSlotState::Available;
        result.slot = makeSlotSnapshot(*targetEntry);
        m_lastEvent = "Metal render target pool released slot " + handleDescription(desc.handle) + ".";
        result.success = true;
        result.action = MetalRenderTargetPoolReleaseAction::ReturnedToPool;
        result.diagnostic = m_lastEvent;
        return result;
    }

    MetalRenderTargetPoolDiscardResult discard(const MetalRenderTargetPoolDiscardDesc& desc)
    {
        MetalRenderTargetPoolDiscardResult result;
        result.handle = desc.handle;

        MetalRenderTargetPoolEntry* targetEntry = mutableEntry(desc.handle);
        if (targetEntry == nullptr) {
            m_lastEvent = "Metal render target pool discard failed: handle is invalid.";
            result.diagnostic = m_lastEvent;
            return result;
        }

        result.slot = makeSlotSnapshot(*targetEntry);
        discardEntry(*targetEntry);
        m_lastEvent = "Metal render target pool discarded slot " + handleDescription(desc.handle) + ".";
        result.success = true;
        result.action = MetalRenderTargetPoolDiscardAction::DiscardedTarget;
        result.diagnostic = m_lastEvent;
        return result;
    }

    MetalRenderTargetPoolPruneResult pruneIdle(const MetalRenderTargetPoolPruneDesc& desc)
    {
        MetalRenderTargetPoolPruneResult result;
        result.frameNumber = desc.currentFrameNumber;

        for (MetalRenderTargetPoolEntry& targetEntry : m_entries) {
            if (!targetEntry.isAvailable() || !isEntryIdleExpired(targetEntry, desc.currentFrameNumber)) {
                continue;
            }

            result.discardedSlots.push_back(makeSlotSnapshot(targetEntry));
            discardEntry(targetEntry);
            ++result.prunedCount;
        }

        m_pruneCount += result.prunedCount;
        m_lastEvent = "Metal render target pool pruned " + std::to_string(result.prunedCount) + " idle slots.";
        result.diagnostic = m_lastEvent;
        return result;
    }

    MetalRenderTargetPoolResetResult reset(const MetalRenderTargetPoolResetDesc& desc)
    {
        MetalRenderTargetPoolResetResult result;
        result.action = desc.mode == MetalRenderTargetPoolResetMode::ResetPool
            ? MetalRenderTargetPoolResetAction::ResetPool
            : MetalRenderTargetPoolResetAction::ClearedTargets;

        for (MetalRenderTargetPoolEntry& targetEntry : m_entries) {
            if (targetEntry.isEmpty()) {
                continue;
            }

            result.discardedSlots.push_back(makeSlotSnapshot(targetEntry));
            discardEntry(targetEntry);
            ++result.discardedCount;
        }

        if (desc.mode == MetalRenderTargetPoolResetMode::ResetPool) {
            m_entries.clear();
        }

        if (desc.resetDiagnostics) {
            resetDiagnostics();
        }

        m_lastEvent = desc.mode == MetalRenderTargetPoolResetMode::ResetPool
            ? "Metal render target pool reset."
            : "Metal render target pool cleared.";
        result.diagnostic = m_lastEvent;
        return result;
    }

    MetalRenderTargetPoolEntry* mutableEntry(MetalRenderTargetPoolHandle handle)
    {
        return const_cast<MetalRenderTargetPoolEntry*>(
            static_cast<const MetalRenderTargetPool*>(this)->entry(handle));
    }

    MetalRenderTargetPoolEntry* allocateSlot()
    {
        for (std::size_t index = 0; index < m_entries.size(); ++index) {
            MetalRenderTargetPoolEntry& targetEntry = m_entries[index];
            if (targetEntry.isEmpty()) {
                targetEntry.handle.slotIndex = static_cast<MetalRenderTargetPoolSlotIndex>(index);
                targetEntry.handle.generation = detail::nextPoolGeneration(targetEntry.handle.generation);
                return &targetEntry;
            }
        }

        if (m_entries.size() >= static_cast<std::size_t>(kInvalidMetalRenderTargetPoolSlotIndex)) {
            return nullptr;
        }

        MetalRenderTargetPoolEntry targetEntry;
        targetEntry.handle.slotIndex = static_cast<MetalRenderTargetPoolSlotIndex>(m_entries.size());
        targetEntry.handle.generation = 1;
        m_entries.push_back(std::move(targetEntry));
        return &m_entries.back();
    }

    MetalRenderTargetPoolSlotIndex findReusableSlot(
        const MetalRenderTargetPoolKey& key,
        const MetalRenderTargetReusePolicy& reusePolicy) const
    {
        if (!reusePolicy.isReusable()) {
            return kInvalidMetalRenderTargetPoolSlotIndex;
        }

        MetalRenderTargetPoolSlotIndex bestIndex = kInvalidMetalRenderTargetPoolSlotIndex;
        std::size_t bestWasteBytes = std::numeric_limits<std::size_t>::max();
        const MetalRenderTargetPoolMemoryEstimate requestedEstimate = estimateMemory(key);

        for (std::size_t index = 0; index < m_entries.size(); ++index) {
            const MetalRenderTargetPoolEntry& candidate = m_entries[index];
            if (!candidate.isAvailable() || !canReuse(candidate.key, key, reusePolicy)) {
                continue;
            }
            if (candidate.key.hasExactSize(key)) {
                return static_cast<MetalRenderTargetPoolSlotIndex>(index);
            }

            const MetalRenderTargetPoolMemoryEstimate candidateEstimate = estimateMemory(candidate.key);
            const std::size_t wasteBytes =
                candidateEstimate.totalSizeBytes > requestedEstimate.totalSizeBytes
                ? candidateEstimate.totalSizeBytes - requestedEstimate.totalSizeBytes
                : 0;
            if (wasteBytes < bestWasteBytes) {
                bestWasteBytes = wasteBytes;
                bestIndex = static_cast<MetalRenderTargetPoolSlotIndex>(index);
            }
        }

        return bestIndex;
    }

    void discardEntry(MetalRenderTargetPoolEntry& targetEntry)
    {
        ++m_discardCount;
        targetEntry.state = MetalRenderTargetPoolSlotState::Empty;
        targetEntry.key = {};
        targetEntry.reusePolicy = {};
        targetEntry.createFrame = 0;
        targetEntry.lastAcquireFrame = 0;
        targetEntry.lastReleaseFrame = 0;
        targetEntry.acquireCount = 0;
        targetEntry.clearColor = {};
        targetEntry.clearDepth = 1.0;
        targetEntry.debugLabel.clear();
        targetEntry.handle.generation = detail::nextPoolGeneration(targetEntry.handle.generation);
    }

    bool isEntryIdleExpired(const MetalRenderTargetPoolEntry& targetEntry, uint64_t currentFrameNumber) const
    {
        const uint32_t maxIdleFrames = targetEntry.reusePolicy.maxIdleFrames;
        return maxIdleFrames == 0 ||
            (currentFrameNumber >= targetEntry.lastReleaseFrame &&
                currentFrameNumber - targetEntry.lastReleaseFrame >= static_cast<uint64_t>(maxIdleFrames));
    }

    std::size_t countSlots(MetalRenderTargetPoolSlotState state) const
    {
        return static_cast<std::size_t>(std::count_if(
            m_entries.begin(),
            m_entries.end(),
            [state](const MetalRenderTargetPoolEntry& targetEntry) {
                return targetEntry.state == state;
            }));
    }

    MetalRenderTargetPoolEntryDiagnostics makeEntryDiagnostics(
        const MetalRenderTargetPoolEntry& targetEntry) const
    {
        const MetalRenderTargetPoolSlotSnapshot snapshot = makeSlotSnapshot(targetEntry);

        MetalRenderTargetPoolEntryDiagnostics diagnostics;
        diagnostics.handle = snapshot.handle;
        diagnostics.state = snapshot.state;
        diagnostics.key = snapshot.key;
        diagnostics.reusePolicy = snapshot.reusePolicy;
        diagnostics.memoryEstimate = snapshot.memoryEstimate;
        diagnostics.descriptor = snapshot.descriptor;
        diagnostics.createFrame = snapshot.createFrame;
        diagnostics.lastAcquireFrame = snapshot.lastAcquireFrame;
        diagnostics.lastReleaseFrame = snapshot.lastReleaseFrame;
        diagnostics.acquireCount = snapshot.acquireCount;
        diagnostics.clearColor = snapshot.clearColor;
        diagnostics.clearDepth = snapshot.clearDepth;
        diagnostics.debugLabel = snapshot.debugLabel;
        diagnostics.stateName = slotStateName(targetEntry.state);
        diagnostics.reuseModeName = reuseModeName(targetEntry.reusePolicy.mode);
        diagnostics.keyString = keyString(targetEntry.key);
        return diagnostics;
    }

    MetalRenderTargetPoolSlotSnapshot makeSlotSnapshot(const MetalRenderTargetPoolEntry& targetEntry) const
    {
        MetalRenderTargetPoolSlotSnapshot snapshot;
        snapshot.handle = targetEntry.handle;
        snapshot.state = targetEntry.state;
        snapshot.key = targetEntry.key;
        snapshot.reusePolicy = targetEntry.reusePolicy;
        snapshot.memoryEstimate = estimateMemory(targetEntry.key);
        snapshot.descriptor = makeDescriptor(
            targetEntry.key,
            targetEntry.debugLabel.c_str(),
            targetEntry.clearColor,
            targetEntry.clearDepth);
        snapshot.createFrame = targetEntry.createFrame;
        snapshot.lastAcquireFrame = targetEntry.lastAcquireFrame;
        snapshot.lastReleaseFrame = targetEntry.lastReleaseFrame;
        snapshot.acquireCount = targetEntry.acquireCount;
        snapshot.clearColor = targetEntry.clearColor;
        snapshot.clearDepth = targetEntry.clearDepth;
        snapshot.debugLabel = targetEntry.debugLabel;
        return snapshot;
    }

    static void addEstimateToTotal(
        const MetalRenderTargetPoolMemoryEstimate& estimate,
        std::size_t& total,
        bool& overflowed)
    {
        std::size_t nextTotal = 0;
        if (!detail::addPoolSize(total, estimate.totalSizeBytes, nextTotal)) {
            overflowed = true;
            return;
        }
        total = nextTotal;
    }

    static bool attachmentSizeBytes(
        std::size_t pixelCount,
        MetalTextureFormat format,
        std::size_t& sizeBytes)
    {
        const std::size_t pixelSizeBytes = bytesPerPixel(format);
        return pixelSizeBytes != 0 && detail::multiplyPoolSize(pixelCount, pixelSizeBytes, sizeBytes);
    }

    static std::size_t bytesPerPixel(MetalTextureFormat format)
    {
        switch (format) {
        case MetalTextureFormat::R8Unorm:
            return 1;
        case MetalTextureFormat::BGRA8Unorm:
        case MetalTextureFormat::BGRA8UnormSrgb:
        case MetalTextureFormat::RGBA8Unorm:
        case MetalTextureFormat::RGBA8UnormSrgb:
        case MetalTextureFormat::Depth32Float:
            return 4;
        }

        return 0;
    }

    static std::string labelForDesc(const MetalRenderTargetDesc& desc, const char* debugLabel)
    {
        if (debugLabel != nullptr) {
            return labelString(debugLabel);
        }
        return desc.label;
    }

    static std::string labelString(const char* label)
    {
        return label == nullptr ? std::string{} : std::string(label);
    }

    std::vector<MetalRenderTargetPoolEntry> m_entries;
    MetalRenderTargetReusePolicy m_defaultReusePolicy;
    std::size_t m_acquireCount = 0;
    std::size_t m_releaseCount = 0;
    std::size_t m_hitCount = 0;
    std::size_t m_missCount = 0;
    std::size_t m_discardCount = 0;
    std::size_t m_pruneCount = 0;
    std::string m_lastEvent;
};

} // namespace mesh2splat::metal
