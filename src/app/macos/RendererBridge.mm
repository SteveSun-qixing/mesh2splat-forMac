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

    M2SRendererStatus* status = [[M2SRendererStatus alloc] init];
    status.runtimeState = bridgeRuntimeState(summary.runtimeState);
    status.diagnosticSeverity = bridgeSeverity(summary.diagnosticSeverity);
    status.statusText = bridgeString(summary.statusText);
    status.loadedScenePath = bridgeString(summary.loadedScenePath);
    status.errorMessage = summary.lastError.empty() ? bridgeString(summary.diagnosticMessage) : bridgeString(summary.lastError);
    status.drawableWidth = summary.drawableWidth;
    status.drawableHeight = summary.drawableHeight;
    status.backingScale = summary.backingScale;
    status.convertedGaussianCount = summary.conversion.convertedGaussianCount != 0 ?
        summary.conversion.convertedGaussianCount :
        summary.convertedGaussianCount;
    status.conversionSamplesPerTriangle = summary.conversion.samplesPerTriangle != 0 ?
        summary.conversion.samplesPerTriangle :
        summary.conversionSamplesPerTriangle;
    status.conversionProgress = summary.conversion.progress != 0.0f ?
        summary.conversion.progress :
        summary.conversionProgress;
    status.gaussianScale = summary.gaussianScale;
    status.converting = summary.conversion.active || summary.isConverting;
    status.hasScene = summary.hasScene;
    status.hasGaussians = summary.hasGaussians || status.convertedGaussianCount > 0;
    status.frameStats = frameStats;
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
