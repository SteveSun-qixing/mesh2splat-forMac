#pragma once

#include "core/InputState.hpp"

#include <cstdint>
#include <memory>
#include <string>

namespace mesh2splat::renderer {

struct RendererInputEvent;

enum class RenderViewMode : uint32_t {
    Combined = 0,
    MeshOnly = 1,
    GaussianOnly = 2,
};

enum class GaussianVisualizationMode : uint32_t {
    Albedo = 0,
    Depth = 1,
    Normal = 2,
    Geometry = 3,
    Overdraw = 4,
    Pbr = 5,
    Final = 6,
};

enum class RendererSceneKind : uint32_t {
    Auto = 0,
    Mesh = 1,
    GaussianPly = 2,
};

enum class RendererRuntimeState : uint32_t {
    Unknown = 0,
    Ready = 1,
    Loading = 2,
    Converting = 3,
    Rendering = 4,
    Failed = 5,
    Exporting = 6,
};

enum class RendererDiagnosticSeverity : uint32_t {
    Info = 0,
    Warning = 1,
    Error = 2,
};

struct RendererResizeRequest {
    uint32_t width = 0;
    uint32_t height = 0;
    float backingScale = 1.0f;
};

struct RendererSceneLoadRequest {
    std::string filePath;
    RendererSceneKind kind = RendererSceneKind::Auto;
    bool replaceCurrentScene = true;
};

struct RendererSceneLoadResult {
    bool accepted = false;
    bool loaded = false;
    std::string diagnostic;
};

struct RendererConversionRequest {
    uint32_t samplesPerTriangle = 0;
    bool forceRebuild = false;
};

struct RendererConversionResult {
    bool accepted = false;
    bool started = false;
    uint32_t samplesPerTriangle = 0;
    uint32_t convertedGaussianCount = 0;
    std::string diagnostic;
};

struct RendererExportPlyRequest {
    std::string filePath;
    uint32_t format = 0;
    float scaleMultiplier = 1.0f;
    bool skipInvalidRecords = true;
};

struct RendererExportPlyResult {
    bool accepted = false;
    bool exported = false;
    uint64_t requestedCount = 0;
    uint64_t writtenCount = 0;
    std::string diagnostic;
};

struct RendererModeRequest {
    RenderViewMode viewMode = RenderViewMode::Combined;
    GaussianVisualizationMode gaussianVisualizationMode = GaussianVisualizationMode::Final;
    float gaussianScale = 1.0f;
};

struct RendererModeResult {
    bool applied = false;
    RenderViewMode viewMode = RenderViewMode::Combined;
    GaussianVisualizationMode gaussianVisualizationMode = GaussianVisualizationMode::Final;
    float gaussianScale = 1.0f;
    std::string diagnostic;
};

struct RendererFrameTick {
    void* renderPassDescriptor = nullptr;
    void* drawable = nullptr;
    core::InputState inputState;
    double deltaTimeSeconds = 0.0;
    uint64_t frameIndex = 0;
};

struct RendererStats {
    uint64_t submittedFrameCount = 0;
    uint64_t completedFrameCount = 0;
    uint64_t failedFrameCount = 0;
    uint64_t submittedConversionCount = 0;
    uint64_t completedConversionCount = 0;
    uint64_t failedConversionCount = 0;
    double lastFrameCpuEncodeMs = 0.0;
    double averageFrameCpuEncodeMs = 0.0;
    double lastFrameGpuMs = 0.0;
    double averageFrameGpuMs = 0.0;
    double lastConversionCpuSubmitMs = 0.0;
    double averageConversionCpuSubmitMs = 0.0;
    double lastConversionGpuMs = 0.0;
    double averageConversionGpuMs = 0.0;
    uint32_t lastFrameGaussianCount = 0;
    uint64_t frameUniformResourceBytes = 0;
    uint64_t sceneResourceBytes = 0;
    uint64_t gaussianResourceBytes = 0;
    uint64_t gaussianSortResourceBytes = 0;
    uint64_t pendingConversionResourceBytes = 0;
    uint64_t trackedResourceBytes = 0;
    bool lastFrameSortedGaussians = false;
    bool lastFrameRenderedMesh = false;
    bool lastFrameRenderedGaussians = false;
};

struct RendererFrameResult {
    bool submitted = false;
    RendererStats stats;
    std::string diagnostic;
};

struct RendererDiagnostics {
    RendererRuntimeState state = RendererRuntimeState::Unknown;
    RendererDiagnosticSeverity severity = RendererDiagnosticSeverity::Info;
    RendererStats stats;
    std::string message;
    std::string lastError;
    std::string loadedScenePath;
    float progress = 0.0f;
    uint32_t convertedGaussianCount = 0;
    uint32_t conversionSamplesPerTriangle = 0;
    RenderViewMode viewMode = RenderViewMode::Combined;
    GaussianVisualizationMode gaussianVisualizationMode = GaussianVisualizationMode::Final;
    float gaussianScale = 1.0f;
    bool converting = false;
    bool hasScene = false;
    bool hasGaussians = false;
};

class Renderer {
public:
    virtual ~Renderer() = default;

    virtual bool initialize() = 0;
    virtual bool loadMeshFile(const std::string& filePath) = 0;
    virtual void resize(uint32_t width, uint32_t height) = 0;
    virtual void setViewMode(RenderViewMode mode) = 0;
    virtual RenderViewMode viewMode() const = 0;
    virtual void setGaussianVisualizationMode(GaussianVisualizationMode mode) = 0;
    virtual GaussianVisualizationMode gaussianVisualizationMode() const = 0;
    virtual void setGaussianScale(float scale) = 0;
    virtual float gaussianScale() const = 0;
    virtual bool setConversionSamplesPerTriangle(uint32_t samplesPerTriangle) = 0;
    virtual uint32_t conversionSamplesPerTriangle() const = 0;
    virtual bool isConvertingGaussians() const = 0;
    virtual uint32_t convertedGaussianCount() const = 0;
    virtual RendererStats rendererStats() const = 0;
    virtual const std::string& lastDiagnostic() const = 0;
    virtual const std::string& loadedMeshPath() const = 0;
    virtual void draw(
        void* renderPassDescriptor,
        void* drawable,
        const core::InputState& inputState,
        double deltaTimeSeconds) = 0;

    virtual void resize(const RendererResizeRequest& request)
    {
        resize(request.width, request.height);
    }

    virtual RendererSceneLoadResult loadScene(const RendererSceneLoadRequest& request)
    {
        RendererSceneLoadResult result;
        result.accepted = !request.filePath.empty();
        if (!result.accepted) {
            result.diagnostic = "Scene file path is empty.";
            return result;
        }

        result.loaded = loadMeshFile(request.filePath);
        result.diagnostic = lastDiagnostic();
        return result;
    }

    virtual RendererConversionResult startConversion(const RendererConversionRequest& request = {})
    {
        RendererConversionResult result;
        result.accepted = !isConvertingGaussians();
        if (!result.accepted) {
            result.diagnostic = "Renderer is already converting gaussians.";
            result.samplesPerTriangle = conversionSamplesPerTriangle();
            return result;
        }

        const uint32_t currentSamples = conversionSamplesPerTriangle();
        const uint32_t requestedSamples =
            request.samplesPerTriangle == 0 ? currentSamples : request.samplesPerTriangle;
        result.started = requestedSamples != currentSamples;
        if (result.started) {
            result.started = setConversionSamplesPerTriangle(requestedSamples);
        } else if (request.forceRebuild || convertedGaussianCount() == 0) {
            result.accepted = false;
            result.diagnostic = "Renderer backend must override startConversion for same-sample rebuilds.";
        }
        result.samplesPerTriangle = conversionSamplesPerTriangle();
        result.convertedGaussianCount = convertedGaussianCount();
        if (result.diagnostic.empty()) {
            result.diagnostic = lastDiagnostic();
        }
        return result;
    }

    virtual RendererModeResult setRenderMode(const RendererModeRequest& request)
    {
        setViewMode(request.viewMode);
        setGaussianVisualizationMode(request.gaussianVisualizationMode);
        setGaussianScale(request.gaussianScale);

        RendererModeResult result;
        result.applied = true;
        result.viewMode = viewMode();
        result.gaussianVisualizationMode = gaussianVisualizationMode();
        result.gaussianScale = gaussianScale();
        result.diagnostic = lastDiagnostic();
        return result;
    }

    virtual RendererExportPlyResult exportPly(const RendererExportPlyRequest& request)
    {
        RendererExportPlyResult result;
        result.accepted = !request.filePath.empty();
        result.requestedCount = convertedGaussianCount();
        if (!result.accepted) {
            result.diagnostic = "PLY export file path is empty.";
            return result;
        }

        result.diagnostic = "PLY export is not implemented by this renderer backend.";
        return result;
    }

    virtual bool handleInputEvent(const RendererInputEvent& event)
    {
        (void)event;
        return false;
    }

    virtual RendererFrameResult tickFrame(const RendererFrameTick& frame)
    {
        draw(frame.renderPassDescriptor, frame.drawable, frame.inputState, frame.deltaTimeSeconds);

        RendererFrameResult result;
        result.submitted = frame.renderPassDescriptor != nullptr && frame.drawable != nullptr;
        result.stats = rendererStats();
        result.diagnostic = lastDiagnostic();
        return result;
    }

    virtual RendererDiagnostics diagnostics() const
    {
        RendererDiagnostics diagnostics;
        diagnostics.stats = rendererStats();
        diagnostics.message = lastDiagnostic();
        diagnostics.lastError = lastDiagnostic();
        diagnostics.loadedScenePath = loadedMeshPath();
        diagnostics.progress = conversionProgress();
        diagnostics.convertedGaussianCount = convertedGaussianCount();
        diagnostics.conversionSamplesPerTriangle = conversionSamplesPerTriangle();
        diagnostics.viewMode = viewMode();
        diagnostics.gaussianVisualizationMode = gaussianVisualizationMode();
        diagnostics.gaussianScale = gaussianScale();
        diagnostics.converting = isConvertingGaussians();
        diagnostics.hasScene = !loadedMeshPath().empty();
        diagnostics.hasGaussians = diagnostics.convertedGaussianCount > 0;
        diagnostics.state = diagnostics.converting ? RendererRuntimeState::Converting : RendererRuntimeState::Ready;
        diagnostics.severity = diagnostics.message.empty() ?
            RendererDiagnosticSeverity::Info :
            RendererDiagnosticSeverity::Warning;
        return diagnostics;
    }

    virtual RendererRuntimeState runtimeState() const
    {
        return diagnostics().state;
    }

    virtual float conversionProgress() const
    {
        if (isConvertingGaussians()) {
            return 0.0f;
        }
        return convertedGaussianCount() == 0 ? 0.0f : 1.0f;
    }

    virtual std::string lastError() const
    {
        return lastDiagnostic();
    }
};

std::unique_ptr<Renderer> createMetalRenderer(void* metalDevice);

} // namespace mesh2splat::renderer
