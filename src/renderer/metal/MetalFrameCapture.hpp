#pragma once

#include "MetalDebugLabels.hpp"

#include <cstdint>
#include <limits>
#include <string>
#include <string_view>
#include <utility>

namespace mesh2splat::metal {

enum class MetalFrameCaptureMarkerKind : uint8_t {
    Begin,
    End,
};

enum class MetalFrameCaptureScope : uint8_t {
    Frame,
    CommandBuffer,
    Pass,
};

enum class MetalFrameCaptureRequestState : uint8_t {
    Idle,
    Pending,
    Capturing,
    Completed,
};

inline const char* metalFrameCaptureMarkerKindName(MetalFrameCaptureMarkerKind kind)
{
    switch (kind) {
    case MetalFrameCaptureMarkerKind::Begin:
        return "begin";
    case MetalFrameCaptureMarkerKind::End:
        return "end";
    }

    return "unknown";
}

inline const char* metalFrameCaptureScopeName(MetalFrameCaptureScope scope)
{
    switch (scope) {
    case MetalFrameCaptureScope::Frame:
        return "frame";
    case MetalFrameCaptureScope::CommandBuffer:
        return "command-buffer";
    case MetalFrameCaptureScope::Pass:
        return "pass";
    }

    return "unknown";
}

inline const char* metalFrameCaptureRequestStateName(MetalFrameCaptureRequestState state)
{
    switch (state) {
    case MetalFrameCaptureRequestState::Idle:
        return "idle";
    case MetalFrameCaptureRequestState::Pending:
        return "pending";
    case MetalFrameCaptureRequestState::Capturing:
        return "capturing";
    case MetalFrameCaptureRequestState::Completed:
        return "completed";
    }

    return "unknown";
}

inline MetalDebugLabelKind metalFrameCaptureScopeDebugLabelKind(MetalFrameCaptureScope scope)
{
    switch (scope) {
    case MetalFrameCaptureScope::Frame:
        return MetalDebugLabelKind::Frame;
    case MetalFrameCaptureScope::CommandBuffer:
        return MetalDebugLabelKind::CommandBuffer;
    case MetalFrameCaptureScope::Pass:
        return MetalDebugLabelKind::Pass;
    }

    return MetalDebugLabelKind::Frame;
}

struct MetalFrameCaptureRequest {
    static constexpr uint64_t kAnyFrameIndex = std::numeric_limits<uint64_t>::max();

    bool requested = false;
    uint64_t frameIndex = kAnyFrameIndex;
    std::string reason;
    bool oneShot = true;
    MetalFrameCaptureScope scope = MetalFrameCaptureScope::Frame;
    std::string label;

    bool isRequested() const
    {
        return requested;
    }

    bool hasSpecificFrame() const
    {
        return frameIndex != kAnyFrameIndex;
    }

    bool matchesFrame(uint64_t currentFrameIndex) const
    {
        return requested && (!hasSpecificFrame() || frameIndex == currentFrameIndex);
    }

    bool capturesAnyFrame() const
    {
        return requested && !hasSpecificFrame();
    }

    explicit operator bool() const
    {
        return requested;
    }
};

struct MetalFrameCaptureMarkerMetadata {
    MetalFrameCaptureMarkerKind kind = MetalFrameCaptureMarkerKind::Begin;
    MetalFrameCaptureScope scope = MetalFrameCaptureScope::Frame;
    uint64_t frameIndex = 0;
    bool captureRequested = false;
    uint64_t captureFrameIndex = MetalFrameCaptureRequest::kAnyFrameIndex;
    std::string captureReason;
    std::string label;
    std::string requestLabel;
    bool oneShot = true;
    MetalFrameCaptureRequestState requestState = MetalFrameCaptureRequestState::Idle;

    bool isBegin() const
    {
        return kind == MetalFrameCaptureMarkerKind::Begin;
    }

    bool isEnd() const
    {
        return kind == MetalFrameCaptureMarkerKind::End;
    }

    bool isCaptureFrame() const
    {
        return captureRequested
            && (captureFrameIndex == MetalFrameCaptureRequest::kAnyFrameIndex
                || captureFrameIndex == frameIndex);
    }

    std::string debugGroupLabel() const
    {
        MetalDebugLabelSuffixes suffixes;
        suffixes.frameIndex = frameIndex;
        const std::string_view role = label.empty() ? "capture" : std::string_view(label);
        std::string debugLabel = composeResourceLabel(
            metalFrameCaptureScopeDebugLabelKind(scope),
            role,
            metalFrameCaptureMarkerKindName(kind),
            suffixes);

        if (!captureReason.empty()) {
            appendDebugLabelPart(debugLabel, "reason", captureReason);
        }
        if (!requestLabel.empty()) {
            appendDebugLabelPart(debugLabel, "request", requestLabel);
        }
        appendDebugLabelPart(debugLabel, "state", metalFrameCaptureRequestStateName(requestState));
        return debugLabel;
    }
};

struct MetalFrameCaptureMarkerPair {
    MetalFrameCaptureMarkerMetadata begin;
    MetalFrameCaptureMarkerMetadata end;
};

struct MetalFrameCaptureDecision {
    bool shouldStart = false;
    bool shouldStop = false;
    bool shouldMark = false;
    MetalFrameCaptureMarkerMetadata marker;

    explicit operator bool() const
    {
        return shouldStart || shouldStop || shouldMark;
    }
};

inline MetalFrameCaptureRequest makeMetalFrameCaptureRequest(
    uint64_t frameIndex,
    std::string reason = std::string(),
    bool oneShot = true,
    MetalFrameCaptureScope scope = MetalFrameCaptureScope::Frame,
    std::string label = std::string())
{
    MetalFrameCaptureRequest request;
    request.requested = true;
    request.frameIndex = frameIndex;
    request.reason = std::move(reason);
    request.oneShot = oneShot;
    request.scope = scope;
    request.label = std::move(label);
    return request;
}

inline MetalFrameCaptureRequest makeMetalFrameCaptureRequest(
    std::string reason = std::string(),
    bool oneShot = true,
    MetalFrameCaptureScope scope = MetalFrameCaptureScope::Frame,
    std::string label = std::string())
{
    return makeMetalFrameCaptureRequest(
        MetalFrameCaptureRequest::kAnyFrameIndex,
        std::move(reason),
        oneShot,
        scope,
        std::move(label));
}

inline MetalFrameCaptureRequest makeMetalFramePassCaptureRequest(
    uint64_t frameIndex,
    std::string reason = std::string(),
    std::string label = std::string(),
    bool oneShot = true)
{
    return makeMetalFrameCaptureRequest(
        frameIndex,
        std::move(reason),
        oneShot,
        MetalFrameCaptureScope::Pass,
        std::move(label));
}

class MetalFrameCapture {
public:
    static constexpr uint64_t kAnyFrameIndex = MetalFrameCaptureRequest::kAnyFrameIndex;

    MetalFrameCapture() = default;

    explicit MetalFrameCapture(MetalFrameCaptureRequest request)
        : m_request(std::move(request))
        , m_state(m_request.requested ? MetalFrameCaptureRequestState::Pending : MetalFrameCaptureRequestState::Idle)
    {
    }

    void setRequest(MetalFrameCaptureRequest request)
    {
        m_request = std::move(request);
        m_state = m_request.requested ? MetalFrameCaptureRequestState::Pending : MetalFrameCaptureRequestState::Idle;
    }

    void requestCapture(
        std::string reason = std::string(),
        bool oneShot = true,
        MetalFrameCaptureScope scope = MetalFrameCaptureScope::Frame,
        std::string label = std::string())
    {
        setRequest(makeMetalFrameCaptureRequest(std::move(reason), oneShot, scope, std::move(label)));
    }

    void requestCaptureForFrame(
        uint64_t frameIndex,
        std::string reason = std::string(),
        bool oneShot = true,
        MetalFrameCaptureScope scope = MetalFrameCaptureScope::Frame,
        std::string label = std::string())
    {
        setRequest(makeMetalFrameCaptureRequest(
            frameIndex,
            std::move(reason),
            oneShot,
            scope,
            std::move(label)));
    }

    void clearRequest()
    {
        m_request = MetalFrameCaptureRequest();
        m_state = MetalFrameCaptureRequestState::Idle;
        m_activeFrameIndex = kAnyFrameIndex;
    }

    const MetalFrameCaptureRequest& request() const
    {
        return m_request;
    }

    bool isCaptureRequested() const
    {
        return m_request.isRequested();
    }

    uint64_t captureFrameIndex() const
    {
        return m_request.frameIndex;
    }

    const std::string& captureReason() const
    {
        return m_request.reason;
    }

    bool isOneShot() const
    {
        return m_request.oneShot;
    }

    MetalFrameCaptureScope captureScope() const
    {
        return m_request.scope;
    }

    const std::string& captureLabel() const
    {
        return m_request.label;
    }

    MetalFrameCaptureRequestState state() const
    {
        return m_state;
    }

    uint64_t activeFrameIndex() const
    {
        return m_activeFrameIndex;
    }

    bool isCapturing() const
    {
        return m_state == MetalFrameCaptureRequestState::Capturing;
    }

    bool shouldCaptureFrame(uint64_t frameIndex) const
    {
        return m_request.matchesFrame(frameIndex);
    }

    bool consumeCaptureForFrame(uint64_t frameIndex)
    {
        if (!shouldCaptureFrame(frameIndex)) {
            return false;
        }

        if (m_request.oneShot) {
            clearRequest();
        }

        return true;
    }

    MetalFrameCaptureMarkerMetadata beginCaptureForFrame(
        uint64_t frameIndex,
        std::string label = std::string())
    {
        MetalFrameCaptureMarkerMetadata marker = beginMarker(frameIndex, std::move(label));
        if (shouldCaptureFrame(frameIndex)) {
            m_state = MetalFrameCaptureRequestState::Capturing;
            m_activeFrameIndex = frameIndex;
            marker.requestState = m_state;
        }
        return marker;
    }

    MetalFrameCaptureMarkerMetadata endCaptureForFrame(
        uint64_t frameIndex,
        std::string label = std::string())
    {
        const bool endingActiveCapture = isCapturing() && m_activeFrameIndex == frameIndex;
        MetalFrameCaptureMarkerMetadata marker = endMarker(frameIndex, std::move(label));
        if (endingActiveCapture) {
            m_state = MetalFrameCaptureRequestState::Completed;
            marker.requestState = m_state;
            m_activeFrameIndex = kAnyFrameIndex;
            if (m_request.oneShot) {
                m_request = MetalFrameCaptureRequest();
            }
        }
        return marker;
    }

    MetalFrameCaptureDecision beginDecision(
        uint64_t frameIndex,
        std::string label = std::string())
    {
        MetalFrameCaptureDecision decision;
        decision.marker = beginCaptureForFrame(frameIndex, std::move(label));
        decision.shouldStart = decision.marker.isCaptureFrame();
        decision.shouldMark = decision.shouldStart;
        return decision;
    }

    MetalFrameCaptureDecision endDecision(
        uint64_t frameIndex,
        std::string label = std::string())
    {
        MetalFrameCaptureDecision decision;
        const bool endingActiveCapture = isCapturing() && m_activeFrameIndex == frameIndex;
        decision.marker = endCaptureForFrame(frameIndex, std::move(label));
        decision.shouldStop = endingActiveCapture;
        decision.shouldMark = decision.shouldStop;
        return decision;
    }

    MetalFrameCaptureMarkerMetadata beginMarker(
        uint64_t frameIndex,
        std::string label = std::string()) const
    {
        return makeMarker(MetalFrameCaptureMarkerKind::Begin, frameIndex, std::move(label));
    }

    MetalFrameCaptureMarkerMetadata endMarker(
        uint64_t frameIndex,
        std::string label = std::string()) const
    {
        return makeMarker(MetalFrameCaptureMarkerKind::End, frameIndex, std::move(label));
    }

    MetalFrameCaptureMarkerPair markers(
        uint64_t frameIndex,
        std::string label = std::string()) const
    {
        MetalFrameCaptureMarkerPair pair;
        pair.begin = beginMarker(frameIndex, label);
        pair.end = endMarker(frameIndex, std::move(label));
        return pair;
    }

private:
    MetalFrameCaptureMarkerMetadata makeMarker(
        MetalFrameCaptureMarkerKind kind,
        uint64_t frameIndex,
        std::string label) const
    {
        MetalFrameCaptureMarkerMetadata metadata;
        metadata.kind = kind;
        metadata.scope = m_request.scope;
        metadata.frameIndex = frameIndex;
        metadata.captureRequested = m_request.requested;
        metadata.captureFrameIndex = m_request.frameIndex;
        metadata.captureReason = m_request.reason;
        metadata.label = std::move(label);
        metadata.requestLabel = m_request.label;
        metadata.oneShot = m_request.oneShot;
        metadata.requestState = m_state;
        return metadata;
    }

    MetalFrameCaptureRequest m_request;
    MetalFrameCaptureRequestState m_state = MetalFrameCaptureRequestState::Idle;
    uint64_t m_activeFrameIndex = kAnyFrameIndex;
};

} // namespace mesh2splat::metal
