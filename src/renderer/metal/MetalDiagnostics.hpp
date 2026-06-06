#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <limits>
#include <string>
#include <utility>
#include <vector>

namespace mesh2splat::metal {

enum class MetalDiagnosticSeverity : uint8_t {
    Info,
    Warning,
    Error,
};

enum class MetalDiagnosticCategory : uint8_t {
    Device,
    Scheduler,
    Pipeline,
    Shader,
    Buffer,
    Texture,
    Resource,
    Frame,
    Pass,
    Renderer,
    Other,
};

constexpr std::size_t kMetalDiagnosticCategoryCount =
    static_cast<std::size_t>(MetalDiagnosticCategory::Other) + 1;

struct MetalDiagnosticEvent {
    uint64_t sequence = 0;
    uint64_t frameNumber = 0;
    MetalDiagnosticSeverity severity = MetalDiagnosticSeverity::Info;
    MetalDiagnosticCategory category = MetalDiagnosticCategory::Other;
    std::string source;
    std::string message;
    std::string detail;

    bool empty() const { return message.empty() && detail.empty(); }
};

struct MetalDiagnosticSummary {
    uint64_t eventCount = 0;
    uint64_t infoCount = 0;
    uint64_t warningCount = 0;
    uint64_t errorCount = 0;
    std::array<uint64_t, kMetalDiagnosticCategoryCount> categoryCounts{};
    std::size_t retainedEventCount = 0;
    uint64_t droppedEventCount = 0;
    MetalDiagnosticSeverity highestSeverity = MetalDiagnosticSeverity::Info;
    MetalDiagnosticEvent latestEvent;
    MetalDiagnosticEvent latestWarningEvent;
    MetalDiagnosticEvent latestErrorEvent;
    std::string latestMessage;
    std::string latestWarning;
    std::string latestError;

    bool hasEvents() const { return eventCount > 0; }
    bool hasWarnings() const { return warningCount > 0; }
    bool hasErrors() const { return errorCount > 0; }
    bool hasRetainedEvents() const { return retainedEventCount > 0; }
};

struct MetalDiagnosticBridgeStatus {
    MetalDiagnosticSeverity severity = MetalDiagnosticSeverity::Info;
    std::string message;
    std::string lastError;
    uint64_t eventCount = 0;
    uint64_t warningCount = 0;
    uint64_t errorCount = 0;
};

enum class MetalBackendRuntimeState : uint8_t {
    Unknown,
    Unavailable,
    Ready,
    Loading,
    Converting,
    Rendering,
    Exporting,
    Failed,
};

struct MetalBackendStatus {
    MetalBackendRuntimeState state = MetalBackendRuntimeState::Unknown;
    std::string backendName = "metal";
    std::string deviceName;
    bool supported = false;
    bool initialized = false;
    bool shaderLibraryReady = false;
    bool pipelineCacheReady = false;
    bool sceneLoaded = false;
    bool hasGaussians = false;
};

struct MetalFrameTimingDiagnostics {
    uint64_t submittedFrameCount = 0;
    uint64_t completedFrameCount = 0;
    uint64_t failedFrameCount = 0;
    double lastCpuEncodeMs = 0.0;
    double averageCpuEncodeMs = 0.0;
    double lastGpuMs = 0.0;
    double averageGpuMs = 0.0;
    bool lastRenderedMesh = false;
    bool lastRenderedGaussians = false;
    bool lastSortedGaussians = false;
};

struct MetalResourceDiagnostics {
    uint64_t frameUniformBytes = 0;
    uint64_t sceneBytes = 0;
    uint64_t gaussianBytes = 0;
    uint64_t gaussianSortBytes = 0;
    uint64_t pendingConversionBytes = 0;
    uint64_t trackedBytes = 0;
    uint32_t meshCount = 0;
    uint32_t materialCount = 0;
    uint32_t textureCount = 0;
    uint32_t gaussianCount = 0;

    bool empty() const { return trackedBytes == 0 && gaussianCount == 0; }
};

struct MetalConversionDiagnostics {
    bool active = false;
    float progress = 0.0f;
    uint32_t samplesPerTriangle = 0;
    uint32_t convertedGaussianCount = 0;
    uint64_t submittedConversionCount = 0;
    uint64_t completedConversionCount = 0;
    uint64_t failedConversionCount = 0;
    double lastCpuSubmitMs = 0.0;
    double averageCpuSubmitMs = 0.0;
    double lastGpuMs = 0.0;
    double averageGpuMs = 0.0;
};

struct MetalRendererDiagnosticsSnapshot {
    MetalBackendStatus backend;
    MetalDiagnosticSummary diagnostics;
    MetalFrameTimingDiagnostics frameTiming;
    MetalResourceDiagnostics resources;
    MetalConversionDiagnostics conversion;
    std::string statusText;
    std::string loadedScenePath;
    std::string lastError;

    bool hasError() const
    {
        return !lastError.empty() || diagnostics.hasErrors() || backend.state == MetalBackendRuntimeState::Failed;
    }
};

inline const char* metalDiagnosticSeverityName(MetalDiagnosticSeverity severity)
{
    switch (severity) {
    case MetalDiagnosticSeverity::Info:
        return "info";
    case MetalDiagnosticSeverity::Warning:
        return "warning";
    case MetalDiagnosticSeverity::Error:
        return "error";
    }

    return "unknown";
}

inline const char* metalDiagnosticCategoryName(MetalDiagnosticCategory category)
{
    switch (category) {
    case MetalDiagnosticCategory::Device:
        return "device";
    case MetalDiagnosticCategory::Scheduler:
        return "scheduler";
    case MetalDiagnosticCategory::Pipeline:
        return "pipeline";
    case MetalDiagnosticCategory::Shader:
        return "shader";
    case MetalDiagnosticCategory::Buffer:
        return "buffer";
    case MetalDiagnosticCategory::Texture:
        return "texture";
    case MetalDiagnosticCategory::Resource:
        return "resource";
    case MetalDiagnosticCategory::Frame:
        return "frame";
    case MetalDiagnosticCategory::Pass:
        return "pass";
    case MetalDiagnosticCategory::Renderer:
        return "renderer";
    case MetalDiagnosticCategory::Other:
        return "other";
    }

    return "unknown";
}

inline const char* metalBackendRuntimeStateName(MetalBackendRuntimeState state)
{
    switch (state) {
    case MetalBackendRuntimeState::Unknown:
        return "unknown";
    case MetalBackendRuntimeState::Unavailable:
        return "unavailable";
    case MetalBackendRuntimeState::Ready:
        return "ready";
    case MetalBackendRuntimeState::Loading:
        return "loading";
    case MetalBackendRuntimeState::Converting:
        return "converting";
    case MetalBackendRuntimeState::Rendering:
        return "rendering";
    case MetalBackendRuntimeState::Exporting:
        return "exporting";
    case MetalBackendRuntimeState::Failed:
        return "failed";
    }

    return "unknown";
}

inline float metalDiagnosticClampProgress(float progress)
{
    if (progress < 0.0f) {
        return 0.0f;
    }
    if (progress > 1.0f) {
        return 1.0f;
    }
    return progress;
}

inline uint32_t metalDiagnosticSaturatingCount(uint64_t value)
{
    return value > std::numeric_limits<uint32_t>::max()
        ? std::numeric_limits<uint32_t>::max()
        : static_cast<uint32_t>(value);
}

inline bool metalDiagnosticIsAtLeast(
    MetalDiagnosticSeverity value,
    MetalDiagnosticSeverity threshold)
{
    return static_cast<uint8_t>(value) >= static_cast<uint8_t>(threshold);
}

inline std::size_t metalDiagnosticCategoryIndex(MetalDiagnosticCategory category)
{
    return static_cast<std::size_t>(category);
}

inline bool metalDiagnosticCategoryIsValid(MetalDiagnosticCategory category)
{
    return metalDiagnosticCategoryIndex(category) < kMetalDiagnosticCategoryCount;
}

inline std::string metalDiagnosticFormatEvent(const MetalDiagnosticEvent& event)
{
    std::string line = "[";
    line += metalDiagnosticSeverityName(event.severity);
    line += "/";
    line += metalDiagnosticCategoryName(event.category);
    line += "]";

    if (!event.source.empty()) {
        line += " ";
        line += event.source;
        line += ":";
    }

    if (!event.message.empty()) {
        line += " ";
        line += event.message;
    }

    if (!event.detail.empty()) {
        line += " (";
        line += event.detail;
        line += ")";
    }

    return line;
}

inline const std::string& metalDiagnosticLatestSignificantMessage(
    const MetalDiagnosticSummary& summary)
{
    if (!summary.latestError.empty()) {
        return summary.latestError;
    }
    if (!summary.latestWarning.empty()) {
        return summary.latestWarning;
    }
    return summary.latestMessage;
}

inline MetalDiagnosticBridgeStatus makeMetalDiagnosticBridgeStatus(
    const MetalDiagnosticSummary& summary)
{
    MetalDiagnosticBridgeStatus status;
    status.severity = summary.highestSeverity;
    status.message = metalDiagnosticLatestSignificantMessage(summary);
    status.lastError = summary.latestError;
    status.eventCount = summary.eventCount;
    status.warningCount = summary.warningCount;
    status.errorCount = summary.errorCount;
    return status;
}

inline MetalDiagnosticEvent makeMetalDiagnosticEvent(
    MetalDiagnosticSeverity severity,
    MetalDiagnosticCategory category,
    std::string message,
    std::string source = std::string(),
    std::string detail = std::string(),
    uint64_t frameNumber = 0)
{
    MetalDiagnosticEvent event;
    event.frameNumber = frameNumber;
    event.severity = severity;
    event.category = category;
    event.source = std::move(source);
    event.message = std::move(message);
    event.detail = std::move(detail);
    return event;
}

class MetalDiagnostics {
public:
    static constexpr std::size_t kDefaultCapacity = 128;

    explicit MetalDiagnostics(std::size_t capacity = kDefaultCapacity)
        : m_capacity(std::max<std::size_t>(capacity, 1))
    {
    }

    void append(MetalDiagnosticEvent event)
    {
        event.sequence = ++m_nextSequence;
        m_latestMessage = metalDiagnosticFormatEvent(event);
        m_latestEvent = event;

        ++m_eventCount;
        switch (event.severity) {
        case MetalDiagnosticSeverity::Info:
            ++m_infoCount;
            break;
        case MetalDiagnosticSeverity::Warning:
            ++m_warningCount;
            m_latestWarningEvent = event;
            m_latestWarning = m_latestMessage;
            break;
        case MetalDiagnosticSeverity::Error:
            ++m_errorCount;
            m_latestErrorEvent = event;
            m_latestError = m_latestMessage;
            break;
        }

        if (metalDiagnosticCategoryIsValid(event.category)) {
            ++m_categoryCounts[metalDiagnosticCategoryIndex(event.category)];
        }

        if (metalDiagnosticIsAtLeast(event.severity, m_highestSeverity)) {
            m_highestSeverity = event.severity;
        }

        if (m_events.size() == m_capacity) {
            m_events.pop_front();
        }
        m_events.push_back(std::move(event));
    }

    void append(
        MetalDiagnosticSeverity severity,
        MetalDiagnosticCategory category,
        std::string message,
        std::string source = std::string(),
        std::string detail = std::string(),
        uint64_t frameNumber = 0)
    {
        append(makeMetalDiagnosticEvent(
            severity,
            category,
            std::move(message),
            std::move(source),
            std::move(detail),
            frameNumber));
    }

    void appendInfo(
        MetalDiagnosticCategory category,
        std::string message,
        std::string source = std::string(),
        std::string detail = std::string(),
        uint64_t frameNumber = 0)
    {
        append(
            MetalDiagnosticSeverity::Info,
            category,
            std::move(message),
            std::move(source),
            std::move(detail),
            frameNumber);
    }

    void appendWarning(
        MetalDiagnosticCategory category,
        std::string message,
        std::string source = std::string(),
        std::string detail = std::string(),
        uint64_t frameNumber = 0)
    {
        append(
            MetalDiagnosticSeverity::Warning,
            category,
            std::move(message),
            std::move(source),
            std::move(detail),
            frameNumber);
    }

    void appendError(
        MetalDiagnosticCategory category,
        std::string message,
        std::string source = std::string(),
        std::string detail = std::string(),
        uint64_t frameNumber = 0)
    {
        append(
            MetalDiagnosticSeverity::Error,
            category,
            std::move(message),
            std::move(source),
            std::move(detail),
            frameNumber);
    }

    void clear()
    {
        m_events.clear();
        m_eventCount = 0;
        m_infoCount = 0;
        m_warningCount = 0;
        m_errorCount = 0;
        m_categoryCounts = {};
        m_highestSeverity = MetalDiagnosticSeverity::Info;
        m_latestEvent = {};
        m_latestWarningEvent = {};
        m_latestErrorEvent = {};
        m_latestMessage.clear();
        m_latestWarning.clear();
        m_latestError.clear();
    }

    void setCapacity(std::size_t capacity)
    {
        m_capacity = std::max<std::size_t>(capacity, 1);
        while (m_events.size() > m_capacity) {
            m_events.pop_front();
        }
        m_latestMessage = m_events.empty() ? std::string() : metalDiagnosticFormatEvent(m_events.back());
    }

    std::size_t capacity() const { return m_capacity; }
    std::size_t size() const { return m_events.size(); }
    bool empty() const { return m_events.empty(); }

    const MetalDiagnosticEvent* latest() const
    {
        return m_eventCount == 0 ? nullptr : &m_latestEvent;
    }

    const MetalDiagnosticEvent* latestWarning() const
    {
        return m_warningCount == 0 ? nullptr : &m_latestWarningEvent;
    }

    const MetalDiagnosticEvent* latestError() const
    {
        return m_errorCount == 0 ? nullptr : &m_latestErrorEvent;
    }

    const std::string& latestMessage() const { return m_latestMessage; }
    const std::string& latestWarningMessage() const { return m_latestWarning; }
    const std::string& latestErrorMessage() const { return m_latestError; }

    MetalDiagnosticBridgeStatus bridgeStatus() const
    {
        return makeMetalDiagnosticBridgeStatus(summary());
    }

    std::vector<MetalDiagnosticEvent> events() const
    {
        return std::vector<MetalDiagnosticEvent>(m_events.begin(), m_events.end());
    }

    std::vector<MetalDiagnosticEvent> events(MetalDiagnosticSeverity minimumSeverity) const
    {
        std::vector<MetalDiagnosticEvent> filtered;
        filtered.reserve(m_events.size());
        for (const MetalDiagnosticEvent& event : m_events) {
            if (metalDiagnosticIsAtLeast(event.severity, minimumSeverity)) {
                filtered.push_back(event);
            }
        }
        return filtered;
    }

    MetalDiagnosticSummary summary() const
    {
        MetalDiagnosticSummary result;
        result.eventCount = m_eventCount;
        result.infoCount = m_infoCount;
        result.warningCount = m_warningCount;
        result.errorCount = m_errorCount;
        result.categoryCounts = m_categoryCounts;
        result.retainedEventCount = m_events.size();
        result.droppedEventCount = m_eventCount > result.retainedEventCount
            ? m_eventCount - result.retainedEventCount
            : 0;
        result.highestSeverity = m_highestSeverity;
        result.latestEvent = m_latestEvent;
        result.latestWarningEvent = m_latestWarningEvent;
        result.latestErrorEvent = m_latestErrorEvent;
        result.latestMessage = m_latestMessage;
        result.latestWarning = m_latestWarning;
        result.latestError = m_latestError;
        return result;
    }

private:
    std::size_t m_capacity = kDefaultCapacity;
    uint64_t m_nextSequence = 0;
    uint64_t m_eventCount = 0;
    uint64_t m_infoCount = 0;
    uint64_t m_warningCount = 0;
    uint64_t m_errorCount = 0;
    std::array<uint64_t, kMetalDiagnosticCategoryCount> m_categoryCounts{};
    MetalDiagnosticSeverity m_highestSeverity = MetalDiagnosticSeverity::Info;
    MetalDiagnosticEvent m_latestEvent;
    MetalDiagnosticEvent m_latestWarningEvent;
    MetalDiagnosticEvent m_latestErrorEvent;
    std::deque<MetalDiagnosticEvent> m_events;
    std::string m_latestMessage;
    std::string m_latestWarning;
    std::string m_latestError;
};

inline void appendMetalDiagnostic(
    MetalDiagnostics& diagnostics,
    MetalDiagnosticSeverity severity,
    MetalDiagnosticCategory category,
    std::string message,
    std::string source = std::string(),
    std::string detail = std::string(),
    uint64_t frameNumber = 0)
{
    diagnostics.append(
        severity,
        category,
        std::move(message),
        std::move(source),
        std::move(detail),
        frameNumber);
}

inline void clearMetalDiagnostics(MetalDiagnostics& diagnostics)
{
    diagnostics.clear();
}

inline const MetalDiagnosticEvent* latestMetalDiagnostic(const MetalDiagnostics& diagnostics)
{
    return diagnostics.latest();
}

inline const MetalDiagnosticEvent* latestMetalDiagnosticWarning(const MetalDiagnostics& diagnostics)
{
    return diagnostics.latestWarning();
}

inline const MetalDiagnosticEvent* latestMetalDiagnosticError(const MetalDiagnostics& diagnostics)
{
    return diagnostics.latestError();
}

inline MetalDiagnosticSummary summarizeMetalDiagnostics(const MetalDiagnostics& diagnostics)
{
    return diagnostics.summary();
}

inline MetalDiagnosticBridgeStatus metalDiagnosticBridgeStatus(const MetalDiagnostics& diagnostics)
{
    return diagnostics.bridgeStatus();
}

} // namespace mesh2splat::metal
