#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <deque>
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
    std::size_t eventCount = 0;
    std::size_t infoCount = 0;
    std::size_t warningCount = 0;
    std::size_t errorCount = 0;
    std::array<std::size_t, 11> categoryCounts{};
    MetalDiagnosticSeverity highestSeverity = MetalDiagnosticSeverity::Info;
    MetalDiagnosticEvent latestEvent;

    bool hasEvents() const { return eventCount > 0; }
    bool hasWarnings() const { return warningCount > 0; }
    bool hasErrors() const { return errorCount > 0; }
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

inline bool metalDiagnosticIsAtLeast(
    MetalDiagnosticSeverity value,
    MetalDiagnosticSeverity threshold)
{
    return static_cast<uint8_t>(value) >= static_cast<uint8_t>(threshold);
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
        m_latestMessage.clear();
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
        return m_events.empty() ? nullptr : &m_events.back();
    }

    const std::string& latestMessage() const { return m_latestMessage; }

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
        result.eventCount = m_events.size();
        if (m_events.empty()) {
            return result;
        }

        result.latestEvent = m_events.back();
        for (const MetalDiagnosticEvent& event : m_events) {
            switch (event.severity) {
            case MetalDiagnosticSeverity::Info:
                ++result.infoCount;
                break;
            case MetalDiagnosticSeverity::Warning:
                ++result.warningCount;
                break;
            case MetalDiagnosticSeverity::Error:
                ++result.errorCount;
                break;
            }

            const std::size_t categoryIndex = metalDiagnosticCategoryIndex(event.category);
            if (categoryIndex < result.categoryCounts.size()) {
                ++result.categoryCounts[categoryIndex];
            }

            if (metalDiagnosticIsAtLeast(event.severity, result.highestSeverity)) {
                result.highestSeverity = event.severity;
            }
        }

        return result;
    }

private:
    static std::size_t metalDiagnosticCategoryIndex(MetalDiagnosticCategory category)
    {
        return static_cast<std::size_t>(category);
    }

    std::size_t m_capacity = kDefaultCapacity;
    uint64_t m_nextSequence = 0;
    std::deque<MetalDiagnosticEvent> m_events;
    std::string m_latestMessage;
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

inline MetalDiagnosticSummary summarizeMetalDiagnostics(const MetalDiagnostics& diagnostics)
{
    return diagnostics.summary();
}

} // namespace mesh2splat::metal
