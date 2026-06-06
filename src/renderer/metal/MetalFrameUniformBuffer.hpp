#pragma once

#include "core/FrameData.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

namespace mesh2splat::metal {

class MetalDeviceContext;

class MetalFrameUniformBuffer {
public:
    struct FrameBinding {
        uint32_t requestedFrameIndex = 0;
        uint32_t frameIndex = 0;
        void* nativeBuffer = nullptr;
        std::size_t offset = 0;
        std::size_t size = 0;
        bool isValid = false;
        bool isWrapped = false;
        std::size_t bufferSize = 0;
        std::size_t stride = 0;
        std::size_t alignment = 0;
        uint64_t uploadSerial = 0;
        uint64_t submissionSerial = 0;
        uint64_t completionSerial = 0;
        bool isInFlight = false;
        bool hasUpload = false;
        std::string debugLabel;
    };

    struct Diagnostics {
        uint32_t frameCount = 0;
        std::size_t uniformSize = 0;
        std::size_t uniformAlignment = 0;
        std::size_t frameStride = 0;
        std::size_t totalSizeBytes = 0;
        std::size_t inFlightFrameCount = 0;
        std::size_t uploadedFrameCount = 0;
        std::size_t overwrittenInFlightFrameCount = 0;
        uint64_t lastUploadSerial = 0;
        uint64_t lastSubmissionSerial = 0;
        uint64_t lastCompletionSerial = 0;
        FrameBinding lastBinding;
        std::string debugLabel;
        std::string lastMessage;
    };

    explicit MetalFrameUniformBuffer(MetalDeviceContext& deviceContext, uint32_t frameCount = 3);
    ~MetalFrameUniformBuffer();

    MetalFrameUniformBuffer(const MetalFrameUniformBuffer&) = delete;
    MetalFrameUniformBuffer& operator=(const MetalFrameUniformBuffer&) = delete;

    MetalFrameUniformBuffer(MetalFrameUniformBuffer&&) noexcept;
    MetalFrameUniformBuffer& operator=(MetalFrameUniformBuffer&&) noexcept;

    bool initialize(const char* label = nullptr);
    bool update(uint32_t frameIndex, const core::FrameUniforms& uniforms);
    bool update(uint32_t frameIndex, const core::FrameUniforms& uniforms, const char* debugLabel);
    bool updateViewport(
        uint32_t frameIndex,
        const core::FrameUniforms& cameraUniforms,
        const core::ViewportState& viewport);
    bool updateViewport(
        uint32_t frameIndex,
        const core::FrameUniforms& cameraUniforms,
        const core::ViewportState& viewport,
        const char* debugLabel);
    bool updateSnapshot(
        uint32_t frameIndex,
        const core::FrameUniforms& cameraUniforms,
        const core::FrameInputSnapshot& snapshot);
    bool updateSnapshot(
        uint32_t frameIndex,
        const core::FrameUniforms& cameraUniforms,
        const core::FrameInputSnapshot& snapshot,
        const char* debugLabel);
    void markFrameSubmitted(uint32_t frameIndex, uint64_t submissionSerial = 0);
    void markFrameCompleted(uint32_t frameIndex, uint64_t completionSerial = 0);
    void resetFrame(uint32_t frameIndex);

    bool isValid() const;
    FrameBinding frameBinding(uint32_t frameIndex) const;
    uint32_t normalizeFrameIndex(uint32_t frameIndex) const;
    bool isValidFrameIndex(uint32_t frameIndex) const;
    bool isFrameInFlight(uint32_t frameIndex) const;
    std::size_t inFlightFrameCount() const;
    uint32_t frameCount() const;
    std::size_t frameStride() const;
    std::size_t frameOffset(uint32_t frameIndex) const;
    std::size_t bufferSize() const;
    std::size_t sizeBytes() const;
    void* buffer(uint32_t frameIndex) const;
    uint64_t lastUploadSerial() const;
    Diagnostics diagnostics() const;
    const std::string& lastDiagnostic() const;
    void setDebugLabel(const char* label);
    const std::string& debugLabel() const;
    std::string describeFrame(uint32_t frameIndex) const;

    static std::size_t uniformAlignment();
    static std::size_t uniformSize();
    static std::size_t alignedUniformSize(std::size_t alignment = 0);

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace mesh2splat::metal
