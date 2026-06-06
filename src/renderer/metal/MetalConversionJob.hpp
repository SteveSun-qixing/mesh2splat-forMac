#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace mesh2splat::metal {

using MetalConversionJobId = uint64_t;

constexpr MetalConversionJobId kInvalidMetalConversionJobId = 0;
constexpr std::size_t kDefaultMetalConversionDiagnosticCapacity = 32;

enum class MetalConversionJobState : uint8_t {
    NotStarted,
    Queued,
    PreparingResources,
    Encoding,
    Submitted,
    Completing,
    Completed,
    CancelRequested,
    Cancelled,
    Failed,
};

enum class MetalConversionDiagnosticSeverity : uint8_t {
    Info,
    Warning,
    Error,
};

struct MetalConversionMeshSelection {
    std::vector<std::size_t> meshIndices;
    bool includesAllMeshes = true;

    bool empty() const
    {
        return !includesAllMeshes && meshIndices.empty();
    }

    std::size_t selectedMeshCount() const
    {
        return includesAllMeshes ? 0 : meshIndices.size();
    }

    static MetalConversionMeshSelection allMeshes()
    {
        return {};
    }

    static MetalConversionMeshSelection selectedMeshes(std::vector<std::size_t> indices)
    {
        MetalConversionMeshSelection selection;
        selection.includesAllMeshes = false;
        selection.meshIndices = std::move(indices);
        return selection;
    }
};

struct MetalConversionSettingsSnapshot {
    uint32_t requestedSamplesPerTriangle = 4;
    uint32_t samplesPerTriangle = 4;
    bool replacesSceneResources = false;
    bool revertsSamplesOnFailure = false;
    uint32_t previousSamplesPerTriangle = 4;

    static uint32_t normalizeSamplesPerTriangle(uint32_t requestedSamples)
    {
        if (requestedSamples <= 1) {
            return 1;
        }
        if (requestedSamples <= 4) {
            return 4;
        }
        return 9;
    }

    static MetalConversionSettingsSnapshot fromRequestedSamples(
        uint32_t requestedSamples,
        bool replacesScene = false,
        bool revertsOnFailure = false,
        uint32_t previousSamples = 4)
    {
        MetalConversionSettingsSnapshot snapshot;
        snapshot.requestedSamplesPerTriangle = requestedSamples;
        snapshot.samplesPerTriangle = normalizeSamplesPerTriangle(requestedSamples);
        snapshot.replacesSceneResources = replacesScene;
        snapshot.revertsSamplesOnFailure = revertsOnFailure;
        snapshot.previousSamplesPerTriangle = normalizeSamplesPerTriangle(previousSamples);
        return snapshot;
    }
};

struct MetalConversionOutputCapacity {
    std::size_t plannedGaussianCapacity = 0;
    std::size_t allocatedGaussianCapacity = 0;
    std::size_t allocatedSortCapacity = 0;
    std::size_t gaussianRecordStrideBytes = 0;

    bool hasPlannedOutput() const
    {
        return plannedGaussianCapacity > 0;
    }

    bool hasAllocatedOutput() const
    {
        return allocatedGaussianCapacity > 0;
    }

    bool hasAllocatedSortOutput() const
    {
        return allocatedSortCapacity > 0;
    }

    bool fitsAllocatedBuffers() const
    {
        return plannedGaussianCapacity <= allocatedGaussianCapacity &&
            plannedGaussianCapacity <= allocatedSortCapacity;
    }

    std::size_t minimumAllocatedCapacity() const
    {
        return allocatedGaussianCapacity < allocatedSortCapacity
            ? allocatedGaussianCapacity
            : allocatedSortCapacity;
    }
};

struct MetalConversionProgressSnapshot {
    uint64_t meshesCompleted = 0;
    uint64_t meshesTotal = 0;
    uint64_t drawRangesCompleted = 0;
    uint64_t drawRangesTotal = 0;
    uint64_t trianglesCompleted = 0;
    uint64_t trianglesTotal = 0;
    uint64_t gaussiansProduced = 0;
    uint64_t gaussiansCapacity = 0;

    bool empty() const
    {
        return meshesTotal == 0 && drawRangesTotal == 0 && trianglesTotal == 0 &&
            gaussiansCapacity == 0;
    }

    bool complete() const
    {
        return atOrPastTotal(meshesCompleted, meshesTotal) &&
            atOrPastTotal(drawRangesCompleted, drawRangesTotal) &&
            atOrPastTotal(trianglesCompleted, trianglesTotal) &&
            atOrPastTotal(gaussiansProduced, gaussiansCapacity);
    }

    float fractionComplete() const
    {
        const double meshProgress = fraction(meshesCompleted, meshesTotal);
        const double drawRangeProgress = fraction(drawRangesCompleted, drawRangesTotal);
        const double triangleProgress = fraction(trianglesCompleted, trianglesTotal);
        const double gaussianProgress = fraction(gaussiansProduced, gaussiansCapacity);

        double totalProgress = 0.0;
        double weight = 0.0;
        accumulateProgress(meshProgress, meshesTotal, &totalProgress, &weight);
        accumulateProgress(drawRangeProgress, drawRangesTotal, &totalProgress, &weight);
        accumulateProgress(triangleProgress, trianglesTotal, &totalProgress, &weight);
        accumulateProgress(gaussianProgress, gaussiansCapacity, &totalProgress, &weight);
        if (weight == 0.0) {
            return 0.0f;
        }
        return static_cast<float>(totalProgress / weight);
    }

private:
    static bool atOrPastTotal(uint64_t completed, uint64_t total)
    {
        return total == 0 || completed >= total;
    }

    static double fraction(uint64_t completed, uint64_t total)
    {
        if (total == 0) {
            return 0.0;
        }
        if (completed >= total) {
            return 1.0;
        }
        return static_cast<double>(completed) / static_cast<double>(total);
    }

    static void accumulateProgress(
        double progress,
        uint64_t total,
        double* totalProgress,
        double* weight)
    {
        if (total == 0 || totalProgress == nullptr || weight == nullptr) {
            return;
        }

        *totalProgress += progress;
        *weight += 1.0;
    }
};

struct MetalConversionProgressCounters {
    std::atomic<uint64_t> meshesCompleted{0};
    std::atomic<uint64_t> meshesTotal{0};
    std::atomic<uint64_t> drawRangesCompleted{0};
    std::atomic<uint64_t> drawRangesTotal{0};
    std::atomic<uint64_t> trianglesCompleted{0};
    std::atomic<uint64_t> trianglesTotal{0};
    std::atomic<uint64_t> gaussiansProduced{0};
    std::atomic<uint64_t> gaussiansCapacity{0};

    void reset()
    {
        storeSnapshot({});
    }

    void storeSnapshot(const MetalConversionProgressSnapshot& progress)
    {
        meshesCompleted.store(progress.meshesCompleted, std::memory_order_relaxed);
        meshesTotal.store(progress.meshesTotal, std::memory_order_relaxed);
        drawRangesCompleted.store(progress.drawRangesCompleted, std::memory_order_relaxed);
        drawRangesTotal.store(progress.drawRangesTotal, std::memory_order_relaxed);
        trianglesCompleted.store(progress.trianglesCompleted, std::memory_order_relaxed);
        trianglesTotal.store(progress.trianglesTotal, std::memory_order_relaxed);
        gaussiansProduced.store(progress.gaussiansProduced, std::memory_order_relaxed);
        gaussiansCapacity.store(progress.gaussiansCapacity, std::memory_order_relaxed);
    }

    void setTotals(
        uint64_t meshCount,
        uint64_t drawRangeCount,
        uint64_t triangleCount,
        uint64_t gaussianCapacity)
    {
        meshesTotal.store(meshCount, std::memory_order_relaxed);
        drawRangesTotal.store(drawRangeCount, std::memory_order_relaxed);
        trianglesTotal.store(triangleCount, std::memory_order_relaxed);
        gaussiansCapacity.store(gaussianCapacity, std::memory_order_relaxed);
    }

    void setCompleted(
        uint64_t meshCount,
        uint64_t drawRangeCount,
        uint64_t triangleCount,
        uint64_t gaussianCount)
    {
        meshesCompleted.store(meshCount, std::memory_order_relaxed);
        drawRangesCompleted.store(drawRangeCount, std::memory_order_relaxed);
        trianglesCompleted.store(triangleCount, std::memory_order_relaxed);
        gaussiansProduced.store(gaussianCount, std::memory_order_relaxed);
    }

    void incrementMeshesCompleted(uint64_t count = 1)
    {
        addClamped(meshesCompleted, count);
    }

    void incrementDrawRangesCompleted(uint64_t count = 1)
    {
        addClamped(drawRangesCompleted, count);
    }

    void incrementTrianglesCompleted(uint64_t count)
    {
        addClamped(trianglesCompleted, count);
    }

    void incrementGaussiansProduced(uint64_t count)
    {
        addClamped(gaussiansProduced, count);
    }

    MetalConversionProgressSnapshot snapshot() const
    {
        MetalConversionProgressSnapshot progress;
        progress.meshesCompleted = meshesCompleted.load(std::memory_order_relaxed);
        progress.meshesTotal = meshesTotal.load(std::memory_order_relaxed);
        progress.drawRangesCompleted = drawRangesCompleted.load(std::memory_order_relaxed);
        progress.drawRangesTotal = drawRangesTotal.load(std::memory_order_relaxed);
        progress.trianglesCompleted = trianglesCompleted.load(std::memory_order_relaxed);
        progress.trianglesTotal = trianglesTotal.load(std::memory_order_relaxed);
        progress.gaussiansProduced = gaussiansProduced.load(std::memory_order_relaxed);
        progress.gaussiansCapacity = gaussiansCapacity.load(std::memory_order_relaxed);
        return progress;
    }

private:
    static void addClamped(std::atomic<uint64_t>& counter, uint64_t increment)
    {
        if (increment == 0) {
            return;
        }

        uint64_t current = counter.load(std::memory_order_relaxed);
        while (true) {
            const uint64_t next = std::numeric_limits<uint64_t>::max() - current < increment
                ? std::numeric_limits<uint64_t>::max()
                : current + increment;
            if (counter.compare_exchange_weak(
                    current,
                    next,
                    std::memory_order_relaxed,
                    std::memory_order_relaxed)) {
                return;
            }
        }
    }
};

struct MetalConversionDiagnostic {
    uint64_t sequence = 0;
    MetalConversionDiagnosticSeverity severity = MetalConversionDiagnosticSeverity::Info;
    MetalConversionJobState state = MetalConversionJobState::NotStarted;
    std::string message;

    bool empty() const
    {
        return message.empty();
    }
};

struct MetalConversionDiagnosticsSnapshot {
    uint64_t droppedEntryCount = 0;
    uint64_t nextSequence = 1;
    std::size_t capacity = kDefaultMetalConversionDiagnosticCapacity;
    MetalConversionDiagnostic latest;
    std::vector<MetalConversionDiagnostic> entries;

    bool empty() const
    {
        return entries.empty();
    }

    bool hasDroppedEntries() const
    {
        return droppedEntryCount > 0;
    }

    MetalConversionDiagnosticSeverity lastSeverity() const
    {
        return latest.severity;
    }

    MetalConversionJobState lastState() const
    {
        return latest.state;
    }

    const std::string& lastMessage() const
    {
        return latest.message;
    }
};

struct MetalConversionJobSnapshot {
    MetalConversionJobId id = kInvalidMetalConversionJobId;
    MetalConversionJobState state = MetalConversionJobState::NotStarted;
    MetalConversionMeshSelection meshSelection;
    MetalConversionSettingsSnapshot settings;
    MetalConversionOutputCapacity outputCapacity;
    MetalConversionProgressSnapshot progress;
    bool cancelRequested = false;
    bool terminal = false;
    MetalConversionDiagnosticsSnapshot diagnostics;
};

inline const char* metalConversionJobStateName(MetalConversionJobState state)
{
    switch (state) {
    case MetalConversionJobState::NotStarted:
        return "not-started";
    case MetalConversionJobState::Queued:
        return "queued";
    case MetalConversionJobState::PreparingResources:
        return "preparing-resources";
    case MetalConversionJobState::Encoding:
        return "encoding";
    case MetalConversionJobState::Submitted:
        return "submitted";
    case MetalConversionJobState::Completing:
        return "completing";
    case MetalConversionJobState::Completed:
        return "completed";
    case MetalConversionJobState::CancelRequested:
        return "cancel-requested";
    case MetalConversionJobState::Cancelled:
        return "cancelled";
    case MetalConversionJobState::Failed:
        return "failed";
    }

    return "unknown";
}

inline const char* metalConversionDiagnosticSeverityName(MetalConversionDiagnosticSeverity severity)
{
    switch (severity) {
    case MetalConversionDiagnosticSeverity::Info:
        return "info";
    case MetalConversionDiagnosticSeverity::Warning:
        return "warning";
    case MetalConversionDiagnosticSeverity::Error:
        return "error";
    }

    return "unknown";
}

class MetalConversionJob {
public:
    MetalConversionJob()
        : m_id(nextJobId())
    {
    }

    MetalConversionJob(
        MetalConversionMeshSelection selection,
        MetalConversionSettingsSnapshot settings,
        MetalConversionOutputCapacity capacity,
        std::size_t diagnosticCapacity = kDefaultMetalConversionDiagnosticCapacity)
        : MetalConversionJob(
              nextJobId(),
              std::move(selection),
              settings,
              capacity,
              diagnosticCapacity)
    {
    }

    MetalConversionJob(
        MetalConversionJobId id,
        MetalConversionMeshSelection selection,
        MetalConversionSettingsSnapshot settings,
        MetalConversionOutputCapacity capacity,
        std::size_t diagnosticCapacity = kDefaultMetalConversionDiagnosticCapacity)
        : m_id(id == kInvalidMetalConversionJobId ? nextJobId() : id)
        , m_meshSelection(std::move(selection))
        , m_settings(settings)
        , m_outputCapacity(capacity)
        , m_diagnosticCapacity(diagnosticCapacity)
    {
        const uint64_t plannedCapacity = clampedToUint64(m_outputCapacity.plannedGaussianCapacity);
        m_progress.gaussiansCapacity.store(plannedCapacity, std::memory_order_relaxed);
    }

    MetalConversionJob(const MetalConversionJob&) = delete;
    MetalConversionJob& operator=(const MetalConversionJob&) = delete;
    MetalConversionJob(MetalConversionJob&&) = delete;
    MetalConversionJob& operator=(MetalConversionJob&&) = delete;

    MetalConversionJobId id() const
    {
        return m_id;
    }

    const MetalConversionMeshSelection& meshSelection() const
    {
        return m_meshSelection;
    }

    const MetalConversionSettingsSnapshot& settings() const
    {
        return m_settings;
    }

    const MetalConversionOutputCapacity& outputCapacity() const
    {
        return m_outputCapacity;
    }

    void updateOutputCapacity(MetalConversionOutputCapacity capacity)
    {
        m_outputCapacity = capacity;
        m_progress.gaussiansCapacity.store(
            clampedToUint64(capacity.plannedGaussianCapacity),
            std::memory_order_relaxed);
    }

    MetalConversionJobState state() const
    {
        return m_state.load(std::memory_order_acquire);
    }

    const char* stateName() const
    {
        return metalConversionJobStateName(state());
    }

    bool setState(MetalConversionJobState nextState)
    {
        MetalConversionJobState expected = state();
        return transitionFrom(expected, nextState);
    }

    bool transitionFrom(MetalConversionJobState expectedState, MetalConversionJobState nextState)
    {
        return m_state.compare_exchange_strong(
            expectedState,
            nextState,
            std::memory_order_acq_rel,
            std::memory_order_acquire);
    }

    bool markQueued()
    {
        return setState(MetalConversionJobState::Queued);
    }

    bool markPreparingResources()
    {
        return setState(MetalConversionJobState::PreparingResources);
    }

    bool markEncoding()
    {
        return setState(MetalConversionJobState::Encoding);
    }

    bool markSubmitted()
    {
        return setState(MetalConversionJobState::Submitted);
    }

    bool markCompleting()
    {
        return setState(MetalConversionJobState::Completing);
    }

    bool markCompleted()
    {
        clearCancelRequest();
        return setState(MetalConversionJobState::Completed);
    }

    bool markCancelled()
    {
        m_cancelRequested.store(true, std::memory_order_release);
        return setState(MetalConversionJobState::Cancelled);
    }

    bool markFailed()
    {
        return setState(MetalConversionJobState::Failed);
    }

    bool isTerminal() const
    {
        return isTerminalState(state());
    }

    bool isActive() const
    {
        const MetalConversionJobState currentState = state();
        return currentState == MetalConversionJobState::Queued ||
            currentState == MetalConversionJobState::PreparingResources ||
            currentState == MetalConversionJobState::Encoding ||
            currentState == MetalConversionJobState::Submitted ||
            currentState == MetalConversionJobState::Completing ||
            currentState == MetalConversionJobState::CancelRequested;
    }

    bool isCancellationRequested() const
    {
        return m_cancelRequested.load(std::memory_order_acquire);
    }

    bool requestCancel()
    {
        m_cancelRequested.store(true, std::memory_order_release);
        MetalConversionJobState currentState = state();
        while (!isTerminalState(currentState)) {
            if (currentState == MetalConversionJobState::CancelRequested) {
                return true;
            }
            if (m_state.compare_exchange_weak(
                    currentState,
                    MetalConversionJobState::CancelRequested,
                    std::memory_order_acq_rel,
                    std::memory_order_acquire)) {
                return true;
            }
        }
        return false;
    }

    void clearCancelRequest()
    {
        m_cancelRequested.store(false, std::memory_order_release);
    }

    MetalConversionProgressCounters& progress()
    {
        return m_progress;
    }

    const MetalConversionProgressCounters& progress() const
    {
        return m_progress;
    }

    void resetProgress()
    {
        m_progress.reset();
        m_progress.gaussiansCapacity.store(
            clampedToUint64(m_outputCapacity.plannedGaussianCapacity),
            std::memory_order_relaxed);
    }

    void setProgressTotals(
        uint64_t meshCount,
        uint64_t drawRangeCount,
        uint64_t triangleCount,
        uint64_t gaussianCapacity)
    {
        m_progress.setTotals(meshCount, drawRangeCount, triangleCount, gaussianCapacity);
    }

    MetalConversionProgressSnapshot progressSnapshot() const
    {
        return m_progress.snapshot();
    }

    float progressFraction() const
    {
        if (state() == MetalConversionJobState::Completed) {
            return 1.0f;
        }
        return progressSnapshot().fractionComplete();
    }

    void setDiagnosticCapacity(std::size_t capacity)
    {
        std::lock_guard<std::mutex> lock(m_diagnosticsMutex);
        m_diagnosticCapacity = capacity;
        trimDiagnosticsLocked();
    }

    std::size_t diagnosticCapacity() const
    {
        std::lock_guard<std::mutex> lock(m_diagnosticsMutex);
        return m_diagnosticCapacity;
    }

    MetalConversionDiagnosticsSnapshot diagnosticsSnapshot() const
    {
        std::lock_guard<std::mutex> lock(m_diagnosticsMutex);

        MetalConversionDiagnosticsSnapshot snapshot;
        snapshot.droppedEntryCount = m_droppedDiagnosticCount;
        snapshot.nextSequence = m_nextDiagnosticSequence;
        snapshot.capacity = m_diagnosticCapacity;
        snapshot.latest = m_latestDiagnostic;
        snapshot.entries = m_diagnostics;
        return snapshot;
    }

    void clearDiagnostics()
    {
        std::lock_guard<std::mutex> lock(m_diagnosticsMutex);
        m_diagnostics.clear();
        m_latestDiagnostic = {};
        m_droppedDiagnosticCount = 0;
        m_nextDiagnosticSequence = 1;
    }

    MetalConversionDiagnostic latestDiagnostic() const
    {
        std::lock_guard<std::mutex> lock(m_diagnosticsMutex);
        return m_latestDiagnostic;
    }

    std::string lastDiagnosticMessage() const
    {
        std::lock_guard<std::mutex> lock(m_diagnosticsMutex);
        return m_latestDiagnostic.message;
    }

    void recordDiagnostic(
        MetalConversionDiagnosticSeverity severity,
        MetalConversionJobState diagnosticState,
        std::string message)
    {
        std::lock_guard<std::mutex> lock(m_diagnosticsMutex);
        MetalConversionDiagnostic diagnostic;
        diagnostic.sequence = m_nextDiagnosticSequence++;
        diagnostic.severity = severity;
        diagnostic.state = diagnosticState;
        diagnostic.message = std::move(message);

        m_latestDiagnostic = diagnostic;
        if (m_diagnosticCapacity == 0) {
            ++m_droppedDiagnosticCount;
            return;
        }

        m_diagnostics.push_back(std::move(diagnostic));
        trimDiagnosticsLocked();
    }

    void recordInfo(MetalConversionJobState diagnosticState, std::string message)
    {
        recordDiagnostic(MetalConversionDiagnosticSeverity::Info, diagnosticState, std::move(message));
    }

    void recordWarning(MetalConversionJobState diagnosticState, std::string message)
    {
        recordDiagnostic(MetalConversionDiagnosticSeverity::Warning, diagnosticState, std::move(message));
    }

    void recordError(MetalConversionJobState diagnosticState, std::string message)
    {
        recordDiagnostic(MetalConversionDiagnosticSeverity::Error, diagnosticState, std::move(message));
        markFailed();
    }

    MetalConversionJobSnapshot snapshot() const
    {
        MetalConversionJobSnapshot jobSnapshot;
        jobSnapshot.id = id();
        jobSnapshot.state = state();
        jobSnapshot.meshSelection = meshSelection();
        jobSnapshot.settings = settings();
        jobSnapshot.outputCapacity = outputCapacity();
        jobSnapshot.progress = progressSnapshot();
        jobSnapshot.cancelRequested = isCancellationRequested();
        jobSnapshot.terminal = isTerminalState(jobSnapshot.state);
        jobSnapshot.diagnostics = diagnosticsSnapshot();
        return jobSnapshot;
    }

private:
    static bool isTerminalState(MetalConversionJobState state)
    {
        return state == MetalConversionJobState::Completed ||
            state == MetalConversionJobState::Cancelled ||
            state == MetalConversionJobState::Failed;
    }

    static uint64_t clampedToUint64(std::size_t value)
    {
        constexpr std::size_t kMaxUint64AsSize =
            static_cast<std::size_t>(std::numeric_limits<uint64_t>::max());
        if (value > kMaxUint64AsSize) {
            return std::numeric_limits<uint64_t>::max();
        }
        return static_cast<uint64_t>(value);
    }

    static MetalConversionJobId nextJobId()
    {
        static std::atomic<MetalConversionJobId> nextId{1};
        const MetalConversionJobId id = nextId.fetch_add(1, std::memory_order_relaxed);
        return id == kInvalidMetalConversionJobId ? nextId.fetch_add(1, std::memory_order_relaxed) : id;
    }

    void trimDiagnosticsLocked()
    {
        if (m_diagnostics.size() <= m_diagnosticCapacity) {
            return;
        }

        const std::size_t entriesToDrop = m_diagnostics.size() - m_diagnosticCapacity;
        m_diagnostics.erase(m_diagnostics.begin(), m_diagnostics.begin() + entriesToDrop);
        m_droppedDiagnosticCount += entriesToDrop;
    }

    MetalConversionJobId m_id = kInvalidMetalConversionJobId;
    MetalConversionMeshSelection m_meshSelection;
    MetalConversionSettingsSnapshot m_settings;
    MetalConversionOutputCapacity m_outputCapacity;
    std::atomic<MetalConversionJobState> m_state{MetalConversionJobState::NotStarted};
    MetalConversionProgressCounters m_progress;
    std::atomic<bool> m_cancelRequested{false};
    mutable std::mutex m_diagnosticsMutex;
    std::size_t m_diagnosticCapacity = kDefaultMetalConversionDiagnosticCapacity;
    uint64_t m_droppedDiagnosticCount = 0;
    uint64_t m_nextDiagnosticSequence = 1;
    MetalConversionDiagnostic m_latestDiagnostic;
    std::vector<MetalConversionDiagnostic> m_diagnostics;
};

} // namespace mesh2splat::metal
