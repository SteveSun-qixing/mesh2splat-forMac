#pragma once

#include <cstdint>
#include <string>

namespace mesh2splat::macos {

enum class MacBridgeViewMode : std::uint32_t {
    Combined = 0,
    MeshOnly = 1,
    GaussianOnly = 2,
};

enum class MacBridgeUiCommandKind : std::uint32_t {
    None = 0,
    OpenDocument = 1,
    OpenScenePath = 2,
    SetViewMode = 3,
    IncreaseGaussianScale = 4,
    DecreaseGaussianScale = 5,
    ResetGaussianScale = 6,
    SetGaussianScale = 7,
    SetConversionSamplesPerTriangle = 8,
    RefreshRendererStatus = 9,
    ApplyRenderSettings = 10,
};

struct MacBridgeUiCommand {
    MacBridgeUiCommandKind kind = MacBridgeUiCommandKind::None;
    std::uint32_t renderMode = 0;
    MacBridgeViewMode viewMode = MacBridgeViewMode::Combined;
    std::string filePath;
    float gaussianScale = 1.0f;
    float exposure = 1.0f;
    float gamma = 2.2f;
    float backgroundBrightness = 0.04f;
    std::uint32_t conversionSamplesPerTriangle = 1;
    bool gaussianSortingEnabled = true;
    bool meshRenderingEnabled = true;
    bool gaussianRenderingEnabled = true;
    bool meshToGaussianConversionEnabled = true;
    std::uint64_t commandId = 0;
};

enum class MacBridgePanelKind : std::uint32_t {
    None = 0,
    FileDialog = 1,
    RendererStatus = 2,
    Error = 3,
};

enum class MacBridgePanelPhase : std::uint32_t {
    Hidden = 0,
    Requested = 1,
    Presenting = 2,
    Visible = 3,
    Dismissing = 4,
};

struct MacBridgePanelState {
    MacBridgePanelKind kind = MacBridgePanelKind::None;
    MacBridgePanelPhase phase = MacBridgePanelPhase::Hidden;
    std::string title;
    std::string message;
    bool isModal = false;
    bool allowsDismissal = true;
    std::uint64_t requestId = 0;
};

enum class MacBridgeFileDialogIntent : std::uint32_t {
    OpenScene = 0,
    ExportGaussianPly = 1,
};

enum class MacBridgeFileDialogStatus : std::uint32_t {
    Empty = 0,
    Accepted = 1,
    Cancelled = 2,
    Failed = 3,
};

struct MacBridgeFileDialogResult {
    MacBridgeFileDialogStatus status = MacBridgeFileDialogStatus::Empty;
    MacBridgeFileDialogIntent intent = MacBridgeFileDialogIntent::OpenScene;
    std::string filePath;
    std::string displayName;
    std::string errorMessage;
    bool securityScoped = false;
    std::uint64_t requestId = 0;
};

enum class MacBridgeRendererRuntimeState : std::uint32_t {
    Unknown = 0,
    Ready = 1,
    Loading = 2,
    Converting = 3,
    Rendering = 4,
    Failed = 5,
    Exporting = 6,
};

enum class MacBridgeDiagnosticSeverity : std::uint32_t {
    Info = 0,
    Warning = 1,
    Error = 2,
};

struct MacBridgeBackendStatus {
    MacBridgeRendererRuntimeState runtimeState = MacBridgeRendererRuntimeState::Unknown;
    std::string backendName = "metal";
    std::string deviceName;
    bool supported = false;
    bool initialized = false;
    bool shaderLibraryReady = false;
    bool pipelineCacheReady = false;
};

struct MacBridgeFrameTimingStatus {
    std::uint64_t submittedFrameCount = 0;
    std::uint64_t completedFrameCount = 0;
    std::uint64_t failedFrameCount = 0;
    double lastCpuEncodeMs = 0.0;
    double averageCpuEncodeMs = 0.0;
    double lastGpuMs = 0.0;
    double averageGpuMs = 0.0;
    bool lastRenderedMesh = false;
    bool lastRenderedGaussians = false;
    bool lastSortedGaussians = false;
};

struct MacBridgeResourceStatus {
    std::uint64_t frameUniformBytes = 0;
    std::uint64_t sceneBytes = 0;
    std::uint64_t gaussianBytes = 0;
    std::uint64_t gaussianSortBytes = 0;
    std::uint64_t pendingConversionBytes = 0;
    std::uint64_t trackedBytes = 0;
    std::uint32_t meshCount = 0;
    std::uint32_t materialCount = 0;
    std::uint32_t textureCount = 0;
    std::uint32_t gaussianCount = 0;
};

struct MacBridgeConversionStatus {
    bool active = false;
    float progress = 0.0f;
    std::uint32_t samplesPerTriangle = 1;
    std::uint32_t convertedGaussianCount = 0;
    std::uint64_t submittedConversionCount = 0;
    std::uint64_t completedConversionCount = 0;
    std::uint64_t failedConversionCount = 0;
    double lastCpuSubmitMs = 0.0;
    double averageCpuSubmitMs = 0.0;
    double lastGpuMs = 0.0;
    double averageGpuMs = 0.0;
};

struct MacBridgeDiagnosticStatus {
    MacBridgeDiagnosticSeverity severity = MacBridgeDiagnosticSeverity::Info;
    std::string message;
    std::string lastError;
    std::uint64_t eventCount = 0;
    std::uint64_t warningCount = 0;
    std::uint64_t errorCount = 0;
};

struct MacBridgeRendererStatusSummary {
    MacBridgeRendererRuntimeState runtimeState = MacBridgeRendererRuntimeState::Unknown;
    MacBridgeDiagnosticSeverity diagnosticSeverity = MacBridgeDiagnosticSeverity::Info;
    MacBridgeViewMode viewMode = MacBridgeViewMode::Combined;
    std::uint32_t gaussianVisualizationMode = 6;
    MacBridgeBackendStatus backend;
    MacBridgeFrameTimingStatus frameTiming;
    MacBridgeResourceStatus resources;
    MacBridgeConversionStatus conversion;
    MacBridgeDiagnosticStatus diagnostics;
    std::string loadedScenePath;
    std::string loadedSceneDisplayName;
    std::string exportPath;
    std::string statusText;
    std::string diagnosticMessage;
    std::string lastError;
    std::uint32_t drawableWidth = 0;
    std::uint32_t drawableHeight = 0;
    float backingScale = 1.0f;
    float conversionProgress = 0.0f;
    std::uint32_t convertedGaussianCount = 0;
    float gaussianScale = 1.0f;
    float exposure = 1.0f;
    float gamma = 2.2f;
    float backgroundBrightness = 0.04f;
    std::uint32_t conversionSamplesPerTriangle = 1;
    std::uint64_t submittedConversionCount = 0;
    std::uint64_t completedConversionCount = 0;
    std::uint64_t failedConversionCount = 0;
    std::uint64_t submittedFrameCount = 0;
    std::uint64_t completedFrameCount = 0;
    std::uint64_t failedFrameCount = 0;
    double lastFrameCpuEncodeMs = 0.0;
    double averageFrameCpuEncodeMs = 0.0;
    double lastFrameGpuMs = 0.0;
    double averageFrameGpuMs = 0.0;
    double lastConversionCpuSubmitMs = 0.0;
    double averageConversionCpuSubmitMs = 0.0;
    double lastConversionGpuMs = 0.0;
    double averageConversionGpuMs = 0.0;
    std::uint64_t frameUniformResourceBytes = 0;
    std::uint64_t sceneResourceBytes = 0;
    std::uint64_t gaussianResourceBytes = 0;
    std::uint64_t gaussianSortResourceBytes = 0;
    std::uint64_t pendingConversionResourceBytes = 0;
    std::uint64_t trackedResourceBytes = 0;
    std::uint32_t meshCount = 0;
    std::uint32_t materialCount = 0;
    std::uint32_t textureCount = 0;
    bool hasScene = false;
    bool hasGaussians = false;
    bool hasVisibleMesh = false;
    bool isConverting = false;
    bool canImportScene = false;
    bool canStartConversion = false;
    bool canExportGaussians = false;
    bool exportMatchesCurrentConversion = false;
    bool meshRenderingEnabled = true;
    bool gaussianRenderingEnabled = true;
    bool gaussianSortingEnabled = true;
    bool meshToGaussianConversionEnabled = true;
    bool lastFrameRenderedMesh = false;
    bool lastFrameRenderedGaussians = false;
    bool lastFrameSortedGaussians = false;
};

inline void normalizeMacBridgeRendererStatusSummary(MacBridgeRendererStatusSummary& summary)
{
    summary.backend.runtimeState = summary.runtimeState;
    summary.frameTiming.submittedFrameCount = summary.submittedFrameCount;
    summary.frameTiming.completedFrameCount = summary.completedFrameCount;
    summary.frameTiming.failedFrameCount = summary.failedFrameCount;
    summary.frameTiming.lastCpuEncodeMs = summary.lastFrameCpuEncodeMs;
    summary.frameTiming.averageCpuEncodeMs = summary.averageFrameCpuEncodeMs;
    summary.frameTiming.lastGpuMs = summary.lastFrameGpuMs;
    summary.frameTiming.averageGpuMs = summary.averageFrameGpuMs;
    summary.frameTiming.lastRenderedMesh = summary.lastFrameRenderedMesh;
    summary.frameTiming.lastRenderedGaussians = summary.lastFrameRenderedGaussians;
    summary.frameTiming.lastSortedGaussians = summary.lastFrameSortedGaussians;

    summary.resources.frameUniformBytes = summary.frameUniformResourceBytes;
    summary.resources.sceneBytes = summary.sceneResourceBytes;
    summary.resources.gaussianBytes = summary.gaussianResourceBytes;
    summary.resources.gaussianSortBytes = summary.gaussianSortResourceBytes;
    summary.resources.pendingConversionBytes = summary.pendingConversionResourceBytes;
    summary.resources.trackedBytes = summary.trackedResourceBytes;
    summary.resources.meshCount = summary.meshCount;
    summary.resources.materialCount = summary.materialCount;
    summary.resources.textureCount = summary.textureCount;
    summary.resources.gaussianCount = summary.convertedGaussianCount;

    summary.conversion.active = summary.isConverting;
    summary.conversion.progress = summary.conversionProgress;
    summary.conversion.samplesPerTriangle = summary.conversionSamplesPerTriangle;
    summary.conversion.convertedGaussianCount = summary.convertedGaussianCount;
    summary.conversion.submittedConversionCount = summary.submittedConversionCount;
    summary.conversion.completedConversionCount = summary.completedConversionCount;
    summary.conversion.failedConversionCount = summary.failedConversionCount;
    summary.conversion.lastCpuSubmitMs = summary.lastConversionCpuSubmitMs;
    summary.conversion.averageCpuSubmitMs = summary.averageConversionCpuSubmitMs;
    summary.conversion.lastGpuMs = summary.lastConversionGpuMs;
    summary.conversion.averageGpuMs = summary.averageConversionGpuMs;

    summary.diagnostics.severity = summary.diagnosticSeverity;
    summary.diagnostics.message = summary.diagnosticMessage;
    summary.diagnostics.lastError = summary.lastError;
}

struct MacBridgeActionResult {
    bool accepted = false;
    bool completed = false;
    std::string message;
    MacBridgeRendererStatusSummary status;
};

} // namespace mesh2splat::macos
