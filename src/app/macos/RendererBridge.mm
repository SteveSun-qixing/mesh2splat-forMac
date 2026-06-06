#include "RendererBridge.hpp"

#include "MacBridgeTypes.hpp"
#include "MetalView.hpp"

#include <string>

namespace {

NSString* bridgeString(const std::string& value)
{
    return value.empty() ? @"" : [NSString stringWithUTF8String:value.c_str()];
}

M2SRendererRuntimeState bridgeRuntimeState(mesh2splat::macos::MacBridgeRendererRuntimeState state)
{
    switch (state) {
    case mesh2splat::macos::MacBridgeRendererRuntimeState::Unknown:
        return M2SRendererRuntimeStateUnknown;
    case mesh2splat::macos::MacBridgeRendererRuntimeState::Ready:
        return M2SRendererRuntimeStateReady;
    case mesh2splat::macos::MacBridgeRendererRuntimeState::Loading:
        return M2SRendererRuntimeStateLoading;
    case mesh2splat::macos::MacBridgeRendererRuntimeState::Converting:
        return M2SRendererRuntimeStateConverting;
    case mesh2splat::macos::MacBridgeRendererRuntimeState::Rendering:
        return M2SRendererRuntimeStateRendering;
    case mesh2splat::macos::MacBridgeRendererRuntimeState::Failed:
        return M2SRendererRuntimeStateFailed;
    case mesh2splat::macos::MacBridgeRendererRuntimeState::Exporting:
        return M2SRendererRuntimeStateExporting;
    }
    return M2SRendererRuntimeStateUnknown;
}

M2SRendererDiagnosticSeverity bridgeSeverity(mesh2splat::macos::MacBridgeDiagnosticSeverity severity)
{
    switch (severity) {
    case mesh2splat::macos::MacBridgeDiagnosticSeverity::Info:
        return M2SRendererDiagnosticSeverityInfo;
    case mesh2splat::macos::MacBridgeDiagnosticSeverity::Warning:
        return M2SRendererDiagnosticSeverityWarning;
    case mesh2splat::macos::MacBridgeDiagnosticSeverity::Error:
        return M2SRendererDiagnosticSeverityError;
    }
    return M2SRendererDiagnosticSeverityInfo;
}

M2SRendererBackendStatus* bridgeBackendStatus(const mesh2splat::macos::MacBridgeRendererStatusSummary& summary)
{
    M2SRendererBackendStatus* backendStatus = [[M2SRendererBackendStatus alloc] init];
    backendStatus.runtimeState =
        summary.backend.runtimeState == mesh2splat::macos::MacBridgeRendererRuntimeState::Unknown ?
        bridgeRuntimeState(summary.runtimeState) :
        bridgeRuntimeState(summary.backend.runtimeState);
    backendStatus.backendName = bridgeString(summary.backend.backendName);
    backendStatus.deviceName = bridgeString(summary.backend.deviceName);
    backendStatus.supported = summary.backend.supported;
    backendStatus.initialized = summary.backend.initialized;
    backendStatus.shaderLibraryReady = summary.backend.shaderLibraryReady;
    backendStatus.pipelineCacheReady = summary.backend.pipelineCacheReady;
    return backendStatus;
}

M2SRendererStatus* bridgeStatus(const mesh2splat::macos::MacBridgeRendererStatusSummary& summary)
{
    M2SRendererFrameStats* frameStats = [[M2SRendererFrameStats alloc] init];
    frameStats.submittedFrameCount = summary.frameTiming.submittedFrameCount != 0 ?
        summary.frameTiming.submittedFrameCount :
        summary.submittedFrameCount;
    frameStats.completedFrameCount = summary.frameTiming.completedFrameCount != 0 ?
        summary.frameTiming.completedFrameCount :
        summary.completedFrameCount;
    frameStats.failedFrameCount = summary.frameTiming.failedFrameCount != 0 ?
        summary.frameTiming.failedFrameCount :
        summary.failedFrameCount;
    frameStats.lastCpuEncodeMs = summary.frameTiming.lastCpuEncodeMs != 0.0 ?
        summary.frameTiming.lastCpuEncodeMs :
        summary.lastFrameCpuEncodeMs;
    frameStats.averageCpuEncodeMs = summary.frameTiming.averageCpuEncodeMs != 0.0 ?
        summary.frameTiming.averageCpuEncodeMs :
        summary.averageFrameCpuEncodeMs;
    frameStats.lastGpuMs = summary.frameTiming.lastGpuMs != 0.0 ?
        summary.frameTiming.lastGpuMs :
        summary.lastFrameGpuMs;
    frameStats.averageGpuMs = summary.frameTiming.averageGpuMs != 0.0 ?
        summary.frameTiming.averageGpuMs :
        summary.averageFrameGpuMs;
    frameStats.lastRenderedMesh = summary.frameTiming.lastRenderedMesh || summary.lastFrameRenderedMesh;
    frameStats.lastRenderedGaussians = summary.frameTiming.lastRenderedGaussians || summary.lastFrameRenderedGaussians;
    frameStats.lastSortedGaussians = summary.frameTiming.lastSortedGaussians || summary.lastFrameSortedGaussians;

    M2SRendererResourceStats* resourceStats = [[M2SRendererResourceStats alloc] init];
    resourceStats.frameUniformBytes = summary.resources.frameUniformBytes != 0 ?
        summary.resources.frameUniformBytes :
        summary.frameUniformResourceBytes;
    resourceStats.sceneBytes = summary.resources.sceneBytes != 0 ?
        summary.resources.sceneBytes :
        summary.sceneResourceBytes;
    resourceStats.gaussianBytes = summary.resources.gaussianBytes != 0 ?
        summary.resources.gaussianBytes :
        summary.gaussianResourceBytes;
    resourceStats.gaussianSortBytes = summary.resources.gaussianSortBytes != 0 ?
        summary.resources.gaussianSortBytes :
        summary.gaussianSortResourceBytes;
    resourceStats.pendingConversionBytes = summary.resources.pendingConversionBytes != 0 ?
        summary.resources.pendingConversionBytes :
        summary.pendingConversionResourceBytes;
    resourceStats.trackedBytes = summary.resources.trackedBytes != 0 ?
        summary.resources.trackedBytes :
        summary.trackedResourceBytes;
    resourceStats.meshCount = summary.resources.meshCount != 0 ?
        summary.resources.meshCount :
        summary.meshCount;
    resourceStats.materialCount = summary.resources.materialCount != 0 ?
        summary.resources.materialCount :
        summary.materialCount;
    resourceStats.textureCount = summary.resources.textureCount != 0 ?
        summary.resources.textureCount :
        summary.textureCount;
    resourceStats.gaussianCount = summary.resources.gaussianCount != 0 ?
        summary.resources.gaussianCount :
        summary.convertedGaussianCount;

    M2SRendererConversionStats* conversionStats = [[M2SRendererConversionStats alloc] init];
    conversionStats.active = summary.conversion.active || summary.isConverting;
    conversionStats.progress = summary.conversion.progress != 0.0f ?
        summary.conversion.progress :
        summary.conversionProgress;
    conversionStats.samplesPerTriangle = summary.conversion.samplesPerTriangle != 0 ?
        summary.conversion.samplesPerTriangle :
        summary.conversionSamplesPerTriangle;
    conversionStats.convertedGaussianCount = summary.conversion.convertedGaussianCount != 0 ?
        summary.conversion.convertedGaussianCount :
        summary.convertedGaussianCount;
    conversionStats.submittedConversionCount = summary.conversion.submittedConversionCount != 0 ?
        summary.conversion.submittedConversionCount :
        summary.submittedConversionCount;
    conversionStats.completedConversionCount = summary.conversion.completedConversionCount != 0 ?
        summary.conversion.completedConversionCount :
        summary.completedConversionCount;
    conversionStats.failedConversionCount = summary.conversion.failedConversionCount != 0 ?
        summary.conversion.failedConversionCount :
        summary.failedConversionCount;
    conversionStats.lastCpuSubmitMs = summary.conversion.lastCpuSubmitMs != 0.0 ?
        summary.conversion.lastCpuSubmitMs :
        summary.lastConversionCpuSubmitMs;
    conversionStats.averageCpuSubmitMs = summary.conversion.averageCpuSubmitMs != 0.0 ?
        summary.conversion.averageCpuSubmitMs :
        summary.averageConversionCpuSubmitMs;
    conversionStats.lastGpuMs = summary.conversion.lastGpuMs != 0.0 ?
        summary.conversion.lastGpuMs :
        summary.lastConversionGpuMs;
    conversionStats.averageGpuMs = summary.conversion.averageGpuMs != 0.0 ?
        summary.conversion.averageGpuMs :
        summary.averageConversionGpuMs;

    M2SRendererStatus* status = [[M2SRendererStatus alloc] init];
    status.runtimeState = bridgeRuntimeState(summary.runtimeState);
    status.diagnosticSeverity = bridgeSeverity(summary.diagnosticSeverity);
    status.statusText = bridgeString(summary.statusText);
    status.loadedScenePath = bridgeString(summary.loadedScenePath);
    status.errorMessage = summary.lastError.empty() ? bridgeString(summary.diagnosticMessage) : bridgeString(summary.lastError);
    status.drawableWidth = summary.drawableWidth;
    status.drawableHeight = summary.drawableHeight;
    status.backingScale = summary.backingScale;
    status.convertedGaussianCount = conversionStats.convertedGaussianCount;
    status.conversionSamplesPerTriangle = conversionStats.samplesPerTriangle;
    status.conversionProgress = conversionStats.progress;
    status.gaussianScale = summary.gaussianScale;
    status.converting = conversionStats.active;
    status.hasScene = summary.hasScene;
    status.hasGaussians = summary.hasGaussians || status.convertedGaussianCount > 0;
    status.frameStats = frameStats;
    status.backendStatus = bridgeBackendStatus(summary);
    status.resourceStats = resourceStats;
    status.conversionStats = conversionStats;
    return status;
}

M2SRendererActionResult* bridgeActionResult(const mesh2splat::macos::MacBridgeActionResult& result)
{
    M2SRendererActionResult* actionResult = [[M2SRendererActionResult alloc] init];
    actionResult.accepted = result.accepted;
    actionResult.completed = result.completed;
    actionResult.message = bridgeString(result.message);
    actionResult.status = bridgeStatus(result.status);
    return actionResult;
}

} // namespace

@implementation M2SRendererFrameStats
@end

@implementation M2SRendererBackendStatus
@end

@implementation M2SRendererResourceStats
@end

@implementation M2SRendererConversionStats
@end

@implementation M2SRendererStatus
@end

@implementation M2SRendererActionResult
@end

@implementation M2SRendererBridge {
    __weak Mesh2SplatMetalView* _metalView;
}

- (instancetype)initWithMetalView:(NSView*)metalView
{
    self = [super init];
    if (self == nil) {
        return nil;
    }

    if ([metalView isKindOfClass:Mesh2SplatMetalView.class]) {
        _metalView = (Mesh2SplatMetalView*)metalView;
    }
    return self;
}

- (M2SRendererStatus*)rendererStatus
{
    if (_metalView == nil) {
        mesh2splat::macos::MacBridgeRendererStatusSummary summary;
        summary.runtimeState = mesh2splat::macos::MacBridgeRendererRuntimeState::Failed;
        summary.diagnosticSeverity = mesh2splat::macos::MacBridgeDiagnosticSeverity::Error;
        summary.statusText = "Renderer unavailable";
        summary.diagnosticMessage = "Metal view is not available.";
        return bridgeStatus(summary);
    }

    return bridgeStatus([_metalView bridgeStatusSummary]);
}

- (M2SRendererActionResult*)importMeshAtURL:(NSURL*)url
{
    mesh2splat::macos::MacBridgeUiCommand command;
    command.kind = mesh2splat::macos::MacBridgeUiCommandKind::OpenScenePath;
    command.filePath = url.path == nil ? std::string() : std::string(url.path.UTF8String);
    return [self performCommand:command fallbackMessage:"Mesh import requested."];
}

- (M2SRendererActionResult*)startConversionWithSamplesPerTriangle:(uint32_t)samplesPerTriangle
{
    mesh2splat::macos::MacBridgeUiCommand command;
    command.kind = mesh2splat::macos::MacBridgeUiCommandKind::SetConversionSamplesPerTriangle;
    command.conversionSamplesPerTriangle = samplesPerTriangle;
    return [self performCommand:command fallbackMessage:"Conversion requested."];
}

- (M2SRendererActionResult*)refreshRendererStatus
{
    mesh2splat::macos::MacBridgeUiCommand command;
    command.kind = mesh2splat::macos::MacBridgeUiCommandKind::RefreshRendererStatus;
    return [self performCommand:command fallbackMessage:"Renderer status refreshed."];
}

- (M2SRendererActionResult*)performCommand:(const mesh2splat::macos::MacBridgeUiCommand&)command
                           fallbackMessage:(const char*)fallbackMessage
{
    if (_metalView == nil) {
        mesh2splat::macos::MacBridgeActionResult result;
        result.accepted = false;
        result.completed = false;
        result.message = fallbackMessage == nullptr ? "Renderer unavailable." : fallbackMessage;
        result.status.runtimeState = mesh2splat::macos::MacBridgeRendererRuntimeState::Failed;
        result.status.diagnosticSeverity = mesh2splat::macos::MacBridgeDiagnosticSeverity::Error;
        result.status.diagnosticMessage = "Metal view is not available.";
        return bridgeActionResult(result);
    }

    return bridgeActionResult([_metalView performBridgeCommand:command]);
}

@end
