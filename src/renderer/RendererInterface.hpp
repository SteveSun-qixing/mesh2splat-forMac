#pragma once

#include "core/InputState.hpp"
#include "renderer/RendererAssetSession.hpp"
#include "renderer/event.hpp"

#include <cstdint>
#include <memory>
#include <string>

namespace mesh2splat::renderer {

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

enum class RendererConversionPhase : uint32_t {
    Idle = 0,
    Queued = 1,
    Preparing = 2,
    Running = 3,
    Completed = 4,
    Failed = 5,
    Cancelled = 6,
};

enum class RendererStateDirtyFlag : uint32_t {
    None = 0,
    LoadedScene = 1u << 0,
    SceneCounts = 1u << 1,
    RenderSettings = 1u << 2,
    ConversionState = 1u << 3,
    FrameStats = 1u << 4,
    Diagnostics = 1u << 5,
    RuntimeState = 1u << 6,
    All = 0x7Fu,
};

using RendererStateDirtyFlags = uint32_t;

struct RendererResizeRequest {
    uint32_t width = 0;
    uint32_t height = 0;
    float backingScale = 1.0f;
    uint64_t requestId = 0;
    bool minimized = false;
};

struct RendererSceneLoadRequest {
    std::string filePath;
    RendererSceneKind kind = RendererSceneKind::Auto;
    bool replaceCurrentScene = true;
    uint64_t requestId = 0;
};

struct RendererLoadedSceneSnapshot {
    bool loaded = false;
    RendererSceneKind kind = RendererSceneKind::Auto;
    std::string filePath;
    std::string displayName;
    uint64_t revision = 0;

    bool empty() const
    {
        return !loaded && filePath.empty() && displayName.empty();
    }

    std::string label() const
    {
        if (!displayName.empty()) {
            return displayName;
        }
        return filePath;
    }
};

struct RendererSceneCounts {
    uint64_t nodeCount = 0;
    uint64_t meshCount = 0;
    uint64_t visibleMeshCount = 0;
    uint64_t primitiveCount = 0;
    uint64_t materialCount = 0;
    uint64_t textureCount = 0;
    uint64_t vertexCount = 0;
    uint64_t triangleCount = 0;
    uint64_t gaussianCount = 0;
    uint64_t visibleGaussianCount = 0;

    bool empty() const
    {
        return nodeCount == 0 &&
            meshCount == 0 &&
            visibleMeshCount == 0 &&
            primitiveCount == 0 &&
            materialCount == 0 &&
            textureCount == 0 &&
            vertexCount == 0 &&
            triangleCount == 0 &&
            gaussianCount == 0 &&
            visibleGaussianCount == 0;
    }

    bool hasRenderableContent() const
    {
        return meshCount > 0 || gaussianCount > 0;
    }

    bool hasVisibleMesh() const
    {
        return visibleMeshCount > 0;
    }
};

struct RendererRenderSettingsSummary {
    uint32_t drawableWidth = 0;
    uint32_t drawableHeight = 0;
    float backingScale = 1.0f;
    RenderViewMode viewMode = RenderViewMode::Combined;
    GaussianVisualizationMode gaussianVisualizationMode = GaussianVisualizationMode::Final;
    float gaussianScale = 1.0f;
    float exposure = 1.0f;
    float gamma = 2.2f;
    float backgroundBrightness = 0.04f;
    float lightPosition[3] = {3.0f, 4.0f, 2.5f};
    float lightIntensity = 1.0f;
    float lightColor[3] = {1.0f, 0.95f, 0.85f};
    uint32_t debugFlags = 0;
    uint32_t conversionSamplesPerTriangle = 1;
    bool meshRenderingEnabled = true;
    bool gaussianRenderingEnabled = true;
    bool gaussianSortingEnabled = true;
    bool meshToGaussianConversionEnabled = true;
    bool depthTestEnabled = true;
    bool lightingEnabled = true;
    bool shadowsEnabled = false;
    bool splitScreenEnabled = false;
    float splitScreenPosition = 0.5f;

    bool emptyDrawable() const
    {
        return drawableWidth == 0 || drawableHeight == 0;
    }
};

struct RendererConversionState {
    RendererConversionPhase phase = RendererConversionPhase::Idle;
    bool active = false;
    bool progressKnown = false;
    float progress = 0.0f;
    uint32_t samplesPerTriangle = 1;
    uint64_t sourceTriangleCount = 0;
    uint64_t targetGaussianCount = 0;
    uint64_t convertedGaussianCount = 0;
    double lastCpuSubmitMs = 0.0;
    double averageCpuSubmitMs = 0.0;
    double lastGpuMs = 0.0;
    double averageGpuMs = 0.0;
    std::string diagnostic;

    bool completed() const
    {
        return phase == RendererConversionPhase::Completed;
    }

    bool failed() const
    {
        return phase == RendererConversionPhase::Failed;
    }
};

struct RendererSceneLoadResult {
    bool accepted = false;
    bool loaded = false;
    std::string diagnostic;
    uint64_t requestId = 0;
    RendererSceneKind kind = RendererSceneKind::Auto;
    std::string filePath;
    std::string displayName;
    RendererSceneCounts sceneCounts;
};

struct RendererConversionRequest {
    uint32_t samplesPerTriangle = 0;
    bool forceRebuild = false;
    uint64_t requestId = 0;
};

struct RendererConversionResult {
    bool accepted = false;
    bool started = false;
    uint32_t samplesPerTriangle = 0;
    uint32_t convertedGaussianCount = 0;
    std::string diagnostic;
    uint64_t requestId = 0;
    RendererConversionState state;
};

struct RendererExportPlyRequest {
    std::string filePath;
    uint32_t format = 0;
    float scaleMultiplier = 1.0f;
    bool skipInvalidRecords = true;
    uint64_t requestId = 0;
};

struct RendererExportPlyResult {
    bool accepted = false;
    bool exported = false;
    uint64_t requestedCount = 0;
    uint64_t writtenCount = 0;
    std::string diagnostic;
    uint64_t requestId = 0;
};

struct RendererModeRequest {
    RenderViewMode viewMode = RenderViewMode::Combined;
    GaussianVisualizationMode gaussianVisualizationMode = GaussianVisualizationMode::Final;
    float gaussianScale = 1.0f;
    float exposure = 1.0f;
    float gamma = 2.2f;
    float backgroundBrightness = 0.04f;
    bool depthTestEnabled = true;
    bool lightingEnabled = true;
    bool shadowsEnabled = false;
    bool splitScreenEnabled = false;
    float splitScreenPosition = 0.5f;
    float lightPosition[3] = {3.0f, 4.0f, 2.5f};
    float lightIntensity = 1.0f;
    float lightColor[3] = {1.0f, 0.95f, 0.85f};
    uint32_t debugFlags = 0;
    bool gaussianSortingEnabled = true;
    bool meshToGaussianConversionEnabled = true;
    uint64_t requestId = 0;
};

struct RendererModeResult {
    bool applied = false;
    RenderViewMode viewMode = RenderViewMode::Combined;
    GaussianVisualizationMode gaussianVisualizationMode = GaussianVisualizationMode::Final;
    float gaussianScale = 1.0f;
    float exposure = 1.0f;
    float gamma = 2.2f;
    float backgroundBrightness = 0.04f;
    bool depthTestEnabled = true;
    bool lightingEnabled = true;
    bool shadowsEnabled = false;
    bool splitScreenEnabled = false;
    float splitScreenPosition = 0.5f;
    float lightPosition[3] = {3.0f, 4.0f, 2.5f};
    float lightIntensity = 1.0f;
    float lightColor[3] = {1.0f, 0.95f, 0.85f};
    uint32_t debugFlags = 0;
    bool gaussianSortingEnabled = true;
    bool meshToGaussianConversionEnabled = true;
    std::string diagnostic;
    uint64_t requestId = 0;
};

struct RendererFrameTick {
    void* renderPassDescriptor = nullptr;
    void* drawable = nullptr;
    core::InputState inputState;
    double deltaTimeSeconds = 0.0;
    uint64_t frameIndex = 0;
    RendererResizeRequest resize;
    uint64_t frameNumber = 0;
    bool resizeRequested = false;
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
    uint64_t shadowResourceBytes = 0;
    uint64_t pendingConversionResourceBytes = 0;
    uint64_t trackedResourceBytes = 0;
    bool lastFrameSortedGaussians = false;
    bool lastFrameRenderedMesh = false;
    bool lastFrameRenderedGaussians = false;
    uint64_t frameNumber = 0;
    uint32_t lastFrameMeshCount = 0;
    uint32_t lastFrameVisibleMeshCount = 0;
    uint64_t lastFrameTriangleCount = 0;
    uint64_t lastFrameDrawCallCount = 0;
};

struct RendererFrameResult {
    bool submitted = false;
    RendererStats stats;
    std::string diagnostic;
    bool drawableAvailable = false;
    uint64_t frameIndex = 0;
    uint64_t frameNumber = 0;
    RendererRuntimeState state = RendererRuntimeState::Unknown;
    RendererSceneCounts sceneCounts;
    RendererConversionState conversion;
    bool renderedMesh = false;
    bool renderedGaussians = false;
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
    uint64_t revision = 0;
    RendererLoadedSceneSnapshot loadedScene;
    RendererAssetSessionSnapshot assetSession;
    RendererSceneCounts sceneCounts;
    RendererRenderSettingsSummary renderSettings;
    RendererConversionState conversion;
    std::string statusText;
    bool hasVisibleMesh = false;
};

struct RendererStateSnapshot {
    uint64_t revision = 0;
    RendererRuntimeState runtimeState = RendererRuntimeState::Unknown;
    RendererDiagnosticSeverity diagnosticSeverity = RendererDiagnosticSeverity::Info;
    RendererLoadedSceneSnapshot loadedScene;
    RendererSceneCounts sceneCounts;
    RendererRenderSettingsSummary renderSettings;
    RendererConversionState conversion;
    RendererStats stats;
    std::string diagnostic;
    std::string lastError;
    std::string statusText;
    RendererStateDirtyFlags dirtyFlags = 0;

    bool dirty() const
    {
        return dirtyFlags != 0;
    }

    bool hasDirtyFlag(RendererStateDirtyFlag flag) const
    {
        return (dirtyFlags & static_cast<RendererStateDirtyFlags>(flag)) != 0;
    }
};

inline void rendererStateSetDirtyFlag(
    RendererStateDirtyFlags& flags,
    RendererStateDirtyFlag flag)
{
    flags |= static_cast<RendererStateDirtyFlags>(flag);
}

inline void rendererStateClearDirtyFlag(
    RendererStateDirtyFlags& flags,
    RendererStateDirtyFlag flag)
{
    flags &= ~static_cast<RendererStateDirtyFlags>(flag);
}

inline float rendererClampSnapshotProgress(float progress)
{
    if (progress < 0.0f) {
        return 0.0f;
    }
    if (progress > 1.0f) {
        return 1.0f;
    }
    return progress;
}

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
        if (request.minimized) {
            return;
        }
        resize(request.width, request.height);
    }

    virtual RendererSceneLoadResult loadScene(const RendererSceneLoadRequest& request)
    {
        RendererSceneLoadResult result;
        result.requestId = request.requestId;
        result.kind = request.kind;
        result.filePath = request.filePath;
        result.accepted = !request.filePath.empty();
        if (!result.accepted) {
            result.diagnostic = "Scene file path is empty.";
            return result;
        }

        result.loaded = loadMeshFile(request.filePath);
        result.displayName = loadedSceneSnapshot().displayName;
        result.sceneCounts = sceneCounts();
        result.diagnostic = lastDiagnostic();
        return result;
    }

    virtual RendererConversionResult startConversion(const RendererConversionRequest& request = {})
    {
        RendererConversionResult result;
        result.requestId = request.requestId;
        result.accepted = !isConvertingGaussians();
        if (!result.accepted) {
            result.diagnostic = "Renderer is already converting gaussians.";
            result.samplesPerTriangle = conversionSamplesPerTriangle();
            result.convertedGaussianCount = convertedGaussianCount();
            result.state = conversionState();
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
        result.state = conversionState();
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
        result.requestId = request.requestId;
        result.applied = true;
        result.viewMode = viewMode();
        result.gaussianVisualizationMode = gaussianVisualizationMode();
        result.gaussianScale = gaussianScale();
        result.exposure = request.exposure;
        result.gamma = request.gamma;
        result.backgroundBrightness = request.backgroundBrightness;
        result.depthTestEnabled = request.depthTestEnabled;
        result.lightingEnabled = request.lightingEnabled;
        result.shadowsEnabled = request.shadowsEnabled;
        result.splitScreenEnabled = request.splitScreenEnabled;
        result.splitScreenPosition = request.splitScreenPosition;
        result.debugFlags = request.debugFlags;
        result.gaussianSortingEnabled = request.gaussianSortingEnabled;
        result.meshToGaussianConversionEnabled = request.meshToGaussianConversionEnabled;
        result.diagnostic = lastDiagnostic();
        return result;
    }

    virtual RendererExportPlyResult exportPly(const RendererExportPlyRequest& request)
    {
        RendererExportPlyResult result;
        result.requestId = request.requestId;
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
        if (frame.resizeRequested) {
            resize(frame.resize);
        }

        draw(frame.renderPassDescriptor, frame.drawable, frame.inputState, frame.deltaTimeSeconds);

        RendererFrameResult result;
        result.drawableAvailable = frame.renderPassDescriptor != nullptr && frame.drawable != nullptr;
        result.submitted = result.drawableAvailable;
        result.frameIndex = frame.frameIndex;
        result.frameNumber = frame.frameNumber;
        result.state = runtimeState();
        result.stats = rendererStats();
        result.sceneCounts = sceneCounts();
        result.conversion = conversionState();
        result.renderedMesh = result.stats.lastFrameRenderedMesh;
        result.renderedGaussians = result.stats.lastFrameRenderedGaussians;
        result.diagnostic = lastDiagnostic();
        return result;
    }

    virtual RendererDiagnostics diagnostics() const
    {
        RendererDiagnostics diagnostics;
        diagnostics.revision = rendererStateRevision();
        diagnostics.stats = rendererStats();
        diagnostics.message = lastDiagnostic();
        diagnostics.lastError = lastDiagnostic();
        diagnostics.loadedScenePath = loadedMeshPath();
        diagnostics.loadedScene = loadedSceneSnapshot();
        diagnostics.assetSession.sourcePath = diagnostics.loadedScene.filePath;
        diagnostics.assetSession.displayName = diagnostics.loadedScene.displayName;
        diagnostics.assetSession.statusText = lastDiagnostic();
        diagnostics.assetSession.hasScene = diagnostics.loadedScene.loaded;
        diagnostics.assetSession.hasGaussians = convertedGaussianCount() > 0;
        diagnostics.sceneCounts = sceneCounts();
        diagnostics.renderSettings = renderSettingsSummary();
        diagnostics.conversion = conversionState();
        diagnostics.progress = diagnostics.conversion.progress;
        diagnostics.convertedGaussianCount = convertedGaussianCount();
        diagnostics.conversionSamplesPerTriangle = conversionSamplesPerTriangle();
        diagnostics.viewMode = viewMode();
        diagnostics.gaussianVisualizationMode = gaussianVisualizationMode();
        diagnostics.gaussianScale = gaussianScale();
        diagnostics.converting = isConvertingGaussians();
        diagnostics.hasScene = diagnostics.loadedScene.loaded || !loadedMeshPath().empty();
        diagnostics.hasGaussians = diagnostics.convertedGaussianCount > 0;
        diagnostics.hasVisibleMesh = diagnostics.sceneCounts.hasVisibleMesh();
        diagnostics.state = runtimeState();
        if (diagnostics.state == RendererRuntimeState::Unknown) {
            diagnostics.state = diagnostics.converting ? RendererRuntimeState::Converting : RendererRuntimeState::Ready;
        }
        diagnostics.severity = diagnostics.message.empty() ?
            RendererDiagnosticSeverity::Info :
            RendererDiagnosticSeverity::Warning;
        diagnostics.statusText = diagnostics.message.empty() ? std::string("Ready") : diagnostics.message;
        return diagnostics;
    }

    virtual RendererRuntimeState runtimeState() const
    {
        if (isConvertingGaussians()) {
            return RendererRuntimeState::Converting;
        }
        return RendererRuntimeState::Ready;
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

    virtual uint64_t rendererStateRevision() const
    {
        return rendererStats().submittedFrameCount;
    }

    virtual RendererLoadedSceneSnapshot loadedSceneSnapshot() const
    {
        RendererLoadedSceneSnapshot loadedScene;
        loadedScene.loaded = !loadedMeshPath().empty();
        loadedScene.kind = RendererSceneKind::Mesh;
        loadedScene.filePath = loadedMeshPath();
        loadedScene.displayName = rendererDisplayNameFromPath(loadedScene.filePath);
        loadedScene.revision = rendererStateRevision();
        return loadedScene;
    }

    virtual RendererSceneCounts sceneCounts() const
    {
        const RendererStats stats = rendererStats();

        RendererSceneCounts counts;
        counts.meshCount = stats.lastFrameMeshCount;
        counts.visibleMeshCount = stats.lastFrameVisibleMeshCount;
        if (counts.visibleMeshCount == 0 && stats.lastFrameRenderedMesh) {
            counts.visibleMeshCount = counts.meshCount == 0 ? 1 : counts.meshCount;
        }
        counts.triangleCount = stats.lastFrameTriangleCount;
        counts.gaussianCount = convertedGaussianCount();
        counts.visibleGaussianCount = stats.lastFrameGaussianCount;
        return counts;
    }

    virtual RendererRenderSettingsSummary renderSettingsSummary() const
    {
        RendererRenderSettingsSummary settings;
        settings.viewMode = viewMode();
        settings.gaussianVisualizationMode = gaussianVisualizationMode();
        settings.gaussianScale = gaussianScale();
        settings.conversionSamplesPerTriangle = conversionSamplesPerTriangle();
        settings.meshRenderingEnabled = settings.viewMode != RenderViewMode::GaussianOnly;
        settings.gaussianRenderingEnabled = settings.viewMode != RenderViewMode::MeshOnly;
        settings.gaussianSortingEnabled = true;
        settings.meshToGaussianConversionEnabled = true;
        return settings;
    }

    virtual RendererConversionState conversionState() const
    {
        const RendererStats stats = rendererStats();

        RendererConversionState conversion;
        conversion.active = isConvertingGaussians();
        conversion.phase = conversion.active ?
            RendererConversionPhase::Running :
            (convertedGaussianCount() == 0 ? RendererConversionPhase::Idle : RendererConversionPhase::Completed);
        conversion.progressKnown = !conversion.active;
        conversion.progress = rendererClampSnapshotProgress(conversionProgress());
        conversion.samplesPerTriangle = conversionSamplesPerTriangle();
        conversion.convertedGaussianCount = convertedGaussianCount();
        conversion.lastCpuSubmitMs = stats.lastConversionCpuSubmitMs;
        conversion.averageCpuSubmitMs = stats.averageConversionCpuSubmitMs;
        conversion.lastGpuMs = stats.lastConversionGpuMs;
        conversion.averageGpuMs = stats.averageConversionGpuMs;
        conversion.diagnostic = lastDiagnostic();
        return conversion;
    }

    virtual RendererStateSnapshot stateSnapshot() const
    {
        RendererStateSnapshot snapshot;
        snapshot.revision = rendererStateRevision();
        snapshot.runtimeState = runtimeState();
        snapshot.loadedScene = loadedSceneSnapshot();
        snapshot.sceneCounts = sceneCounts();
        snapshot.renderSettings = renderSettingsSummary();
        snapshot.conversion = conversionState();
        snapshot.stats = rendererStats();
        snapshot.diagnostic = lastDiagnostic();
        snapshot.lastError = lastError();
        snapshot.diagnosticSeverity = snapshot.diagnostic.empty() ?
            RendererDiagnosticSeverity::Info :
            RendererDiagnosticSeverity::Warning;
        snapshot.statusText = snapshot.diagnostic.empty() ? std::string("Ready") : snapshot.diagnostic;
        return snapshot;
    }

protected:
    static std::string rendererDisplayNameFromPath(const std::string& filePath)
    {
        const std::string::size_type lastSeparator = filePath.find_last_of("/\\");
        if (lastSeparator == std::string::npos) {
            return filePath;
        }
        return filePath.substr(lastSeparator + 1);
    }
};

std::unique_ptr<Renderer> createMetalRenderer(void* metalDevice);

} // namespace mesh2splat::renderer
