#include "MetalView.hpp"

#include "core/AssetFileTypes.hpp"
#include "core/InputState.hpp"
#include "core/PathUtils.hpp"
#include "core/RenderSettings.hpp"
#include "renderer/event.hpp"
#include "renderer/RendererInterface.hpp"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <memory>
#include <string>
#include <string_view>

@class Mesh2SplatMetalViewDelegate;

namespace {

NSString* stringFromUtf8(const std::string& value)
{
    return value.empty() ? @"" : [NSString stringWithUTF8String:value.c_str()];
}

NSString* stringFromUtf8View(std::string_view value)
{
    if (value.empty()) {
        return @"";
    }
    return [[NSString alloc] initWithBytes:value.data()
                                    length:value.size()
                                  encoding:NSUTF8StringEncoding];
}

NSString* truncatedTitleComponent(NSString* value, NSUInteger maxLength)
{
    if (value == nil || value.length <= maxLength) {
        return value == nil ? @"" : value;
    }

    return [[value substringToIndex:maxLength] stringByAppendingString:@"..."];
}

NSArray<UTType*>* meshContentTypes()
{
    NSMutableArray<UTType*>* contentTypes = [NSMutableArray array];
    for (std::string_view extension : mesh2splat::core::kMeshAssetFileExtensions) {
        UTType* contentType = [UTType typeWithFilenameExtension:stringFromUtf8View(extension)];
        if (contentType != nil) {
            [contentTypes addObject:contentType];
        }
    }
    UTType* plyType = [UTType typeWithFilenameExtension:@"ply"];
    if (plyType != nil) {
        [contentTypes addObject:plyType];
    }
    return contentTypes;
}

NSArray<UTType*>* plyContentTypes()
{
    NSMutableArray<UTType*>* contentTypes = [NSMutableArray array];
    UTType* plyType = [UTType typeWithFilenameExtension:@"ply"];
    if (plyType != nil) {
        [contentTypes addObject:plyType];
    }
    return contentTypes;
}

NSString* defaultGaussianExportName(NSString* loadedMeshPath)
{
    if (loadedMeshPath.length == 0) {
        return @"mesh2splat-gaussians.ply";
    }

    const char* utf8Path = loadedMeshPath.UTF8String;
    const std::string stem = mesh2splat::core::pathDisplayName(
        utf8Path == nullptr ? std::string_view{} : std::string_view(utf8Path),
        "mesh2splat");
    return stringFromUtf8(stem + "-gaussians.ply");
}

BOOL meshURLLooksSupported(NSURL* url)
{
    if (url == nil || !url.isFileURL || url.path.UTF8String == nullptr) {
        return NO;
    }

    const std::string_view path(url.path.UTF8String);
    return mesh2splat::core::assetFilePathSupportsIntent(path, mesh2splat::core::AssetFileIntent::LoadMesh) ||
        mesh2splat::core::assetFileKindFromPath(path) == mesh2splat::core::AssetFileKind::Ply ? YES : NO;
}

BOOL urlLooksLikeGaussianPly(NSURL* url)
{
    if (url == nil || !url.isFileURL || url.path.UTF8String == nullptr) {
        return NO;
    }

    return mesh2splat::core::assetFileKindFromPath(std::string_view(url.path.UTF8String)) ==
        mesh2splat::core::AssetFileKind::Ply ? YES : NO;
}

mesh2splat::core::RenderSettingsSnapshot renderSettingsSnapshotFromBridge(
    NSInteger renderMode,
    double splatSize,
    double exposure,
    double gamma,
    double backgroundBrightness,
    NSInteger conversionSamplesPerTriangle,
    BOOL sortingEnabled,
    BOOL meshRenderingEnabled,
    BOOL gaussianRenderingEnabled,
    BOOL conversionEnabled,
    BOOL depthTestEnabled,
    BOOL splitScreenEnabled,
    double splitScreenPosition,
    BOOL lightingEnabled,
    BOOL shadowsEnabled,
    double lightPositionX,
    double lightPositionY,
    double lightPositionZ,
    double lightIntensity,
    double lightColorRed,
    double lightColorGreen,
    double lightColorBlue,
    uint32_t debugFlags)
{
    mesh2splat::core::RenderSettings settings;
    settings.mode = static_cast<mesh2splat::core::RenderMode>(std::max<NSInteger>(0, renderMode));
    settings.enableMeshRendering = meshRenderingEnabled;
    settings.enableGaussianRendering = gaussianRenderingEnabled;
    settings.enableGaussianSorting = sortingEnabled;
    settings.enableMeshToGaussianConversion = conversionEnabled;
    settings.enableDepthTest = depthTestEnabled;
    settings.enableSplitScreen = splitScreenEnabled;
    settings.splitScreenPosition = static_cast<float>(splitScreenPosition);
    settings.gaussianScale = static_cast<float>(splatSize);
    settings.exposure = static_cast<float>(exposure);
    settings.gamma = static_cast<float>(gamma);
    settings.backgroundBrightness = static_cast<float>(backgroundBrightness);
    settings.enableLighting = lightingEnabled;
    settings.enableShadows = shadowsEnabled;
    settings.lightPosition[0] = static_cast<float>(lightPositionX);
    settings.lightPosition[1] = static_cast<float>(lightPositionY);
    settings.lightPosition[2] = static_cast<float>(lightPositionZ);
    settings.lightIntensity = static_cast<float>(lightIntensity);
    settings.lightColor[0] = static_cast<float>(lightColorRed);
    settings.lightColor[1] = static_cast<float>(lightColorGreen);
    settings.lightColor[2] = static_cast<float>(lightColorBlue);
    settings.debugFlags = debugFlags;
    settings.conversionSamplesPerTriangle = conversionSamplesPerTriangle <= 0
        ? 0
        : static_cast<uint32_t>(conversionSamplesPerTriangle);

    return mesh2splat::core::makeRenderSettingsSnapshot(settings);
}

NSURL* firstFileURLFromDraggingInfo(id<NSDraggingInfo> draggingInfo)
{
    NSPasteboard* pasteboard = draggingInfo.draggingPasteboard;
    NSArray<NSURL*>* urls = [pasteboard readObjectsForClasses:@[NSURL.class]
                                                      options:@{ NSPasteboardURLReadingFileURLsOnlyKey : @YES }];
    for (NSURL* url in urls) {
        if (meshURLLooksSupported(url)) {
            return url;
        }
    }
    return nil;
}

uint32_t rendererModifierMaskFromEvent(NSEvent* event)
{
    NSEventModifierFlags flags = event == nil ? 0 : event.modifierFlags;
    uint32_t modifiers = 0;
    if ((flags & NSEventModifierFlagShift) != 0) {
        modifiers |= mesh2splat::core::InputState::ModifierShift;
    }
    if ((flags & NSEventModifierFlagControl) != 0) {
        modifiers |= mesh2splat::core::InputState::ModifierControl;
    }
    if ((flags & NSEventModifierFlagOption) != 0) {
        modifiers |= mesh2splat::core::InputState::ModifierOption;
    }
    if ((flags & NSEventModifierFlagCommand) != 0) {
        modifiers |= mesh2splat::core::InputState::ModifierCommand;
    }
    if ((flags & NSEventModifierFlagCapsLock) != 0) {
        modifiers |= mesh2splat::core::InputState::ModifierCapsLock;
    }
    if ((flags & NSEventModifierFlagFunction) != 0) {
        modifiers |= mesh2splat::core::InputState::ModifierFunction;
    }
    return modifiers;
}

float backingScaleForView(NSView* view)
{
    if (view.window != nil && view.window.backingScaleFactor > 0.0) {
        return static_cast<float>(view.window.backingScaleFactor);
    }
    if (view.window.screen != nil && view.window.screen.backingScaleFactor > 0.0) {
        return static_cast<float>(view.window.screen.backingScaleFactor);
    }
    return 1.0f;
}

mesh2splat::macos::MacBridgeViewMode macViewModeFromRenderer(mesh2splat::renderer::RenderViewMode mode)
{
    switch (mode) {
    case mesh2splat::renderer::RenderViewMode::Combined:
        return mesh2splat::macos::MacBridgeViewMode::Combined;
    case mesh2splat::renderer::RenderViewMode::MeshOnly:
        return mesh2splat::macos::MacBridgeViewMode::MeshOnly;
    case mesh2splat::renderer::RenderViewMode::GaussianOnly:
        return mesh2splat::macos::MacBridgeViewMode::GaussianOnly;
    }
    return mesh2splat::macos::MacBridgeViewMode::Combined;
}

mesh2splat::renderer::RenderViewMode rendererViewModeFromMac(mesh2splat::macos::MacBridgeViewMode mode)
{
    switch (mode) {
    case mesh2splat::macos::MacBridgeViewMode::Combined:
        return mesh2splat::renderer::RenderViewMode::Combined;
    case mesh2splat::macos::MacBridgeViewMode::MeshOnly:
        return mesh2splat::renderer::RenderViewMode::MeshOnly;
    case mesh2splat::macos::MacBridgeViewMode::GaussianOnly:
        return mesh2splat::renderer::RenderViewMode::GaussianOnly;
    }
    return mesh2splat::renderer::RenderViewMode::Combined;
}

mesh2splat::renderer::RenderViewMode rendererViewModeFromRenderMode(NSInteger renderMode,
                                                                     BOOL meshRenderingEnabled,
                                                                     BOOL gaussianRenderingEnabled)
{
    if (meshRenderingEnabled && !gaussianRenderingEnabled) {
        return mesh2splat::renderer::RenderViewMode::MeshOnly;
    }
    if (!meshRenderingEnabled && gaussianRenderingEnabled) {
        return mesh2splat::renderer::RenderViewMode::GaussianOnly;
    }

    switch (renderMode) {
    case 1:
        return mesh2splat::renderer::RenderViewMode::MeshOnly;
    case 2:
        return mesh2splat::renderer::RenderViewMode::GaussianOnly;
    default:
        return mesh2splat::renderer::RenderViewMode::Combined;
    }
}

mesh2splat::renderer::GaussianVisualizationMode gaussianVisualizationModeFromRenderMode(NSInteger renderMode)
{
    switch (renderMode) {
    case 3:
        return mesh2splat::renderer::GaussianVisualizationMode::Albedo;
    case 4:
        return mesh2splat::renderer::GaussianVisualizationMode::Depth;
    case 5:
        return mesh2splat::renderer::GaussianVisualizationMode::Normal;
    case 6:
        return mesh2splat::renderer::GaussianVisualizationMode::Geometry;
    case 7:
        return mesh2splat::renderer::GaussianVisualizationMode::Overdraw;
    case 8:
        return mesh2splat::renderer::GaussianVisualizationMode::Pbr;
    default:
        return mesh2splat::renderer::GaussianVisualizationMode::Final;
    }
}

mesh2splat::macos::MacBridgeRendererRuntimeState macRuntimeStateFromRenderer(mesh2splat::renderer::RendererRuntimeState state)
{
    switch (state) {
    case mesh2splat::renderer::RendererRuntimeState::Unknown:
        return mesh2splat::macos::MacBridgeRendererRuntimeState::Unknown;
    case mesh2splat::renderer::RendererRuntimeState::Ready:
        return mesh2splat::macos::MacBridgeRendererRuntimeState::Ready;
    case mesh2splat::renderer::RendererRuntimeState::Loading:
        return mesh2splat::macos::MacBridgeRendererRuntimeState::Loading;
    case mesh2splat::renderer::RendererRuntimeState::Converting:
        return mesh2splat::macos::MacBridgeRendererRuntimeState::Converting;
    case mesh2splat::renderer::RendererRuntimeState::Rendering:
        return mesh2splat::macos::MacBridgeRendererRuntimeState::Rendering;
    case mesh2splat::renderer::RendererRuntimeState::Failed:
        return mesh2splat::macos::MacBridgeRendererRuntimeState::Failed;
    case mesh2splat::renderer::RendererRuntimeState::Exporting:
        return mesh2splat::macos::MacBridgeRendererRuntimeState::Exporting;
    }
    return mesh2splat::macos::MacBridgeRendererRuntimeState::Unknown;
}

mesh2splat::macos::MacBridgeDiagnosticSeverity macSeverityFromRenderer(mesh2splat::renderer::RendererDiagnosticSeverity severity)
{
    switch (severity) {
    case mesh2splat::renderer::RendererDiagnosticSeverity::Info:
        return mesh2splat::macos::MacBridgeDiagnosticSeverity::Info;
    case mesh2splat::renderer::RendererDiagnosticSeverity::Warning:
        return mesh2splat::macos::MacBridgeDiagnosticSeverity::Warning;
    case mesh2splat::renderer::RendererDiagnosticSeverity::Error:
        return mesh2splat::macos::MacBridgeDiagnosticSeverity::Error;
    }
    return mesh2splat::macos::MacBridgeDiagnosticSeverity::Info;
}

} // namespace

@interface Mesh2SplatMetalView ()

@property (nonatomic, strong) Mesh2SplatMetalViewDelegate* meshDelegate;
@property (nonatomic, strong) NSTrackingArea* pointerTrackingArea;
@property (nonatomic, strong) NSTextField* statusLabel;
@property (nonatomic, copy) NSString* lastDiagnosticMessage;
@property (nonatomic, copy) NSString* lastImportStatus;
@property (nonatomic, copy) NSString* lastConversionStatus;
@property (nonatomic, copy) NSString* lastExportStatus;

- (const mesh2splat::core::InputState&)inputState;
- (void)beginInputFrame;
- (void)dispatchInputEvent:(const mesh2splat::renderer::RendererInputEvent&)event;
- (void)openMeshDocument;
- (void)exportGaussianPlyDocument;
- (void)configureStatusLabel;
- (void)updateStatusLabelWithTitle:(NSString*)title;
- (void)updateDrawableSizeForBackingScale;
- (void)updateRenderLoopState;

@end

@interface Mesh2SplatMetalViewDelegate : NSObject <MTKViewDelegate>

- (instancetype)initWithView:(Mesh2SplatMetalView*)view;
- (BOOL)loadMeshAtPath:(NSString*)path;
- (mesh2splat::renderer::RendererExportPlyResult)exportPlyAtPath:(NSString*)path;
- (mesh2splat::renderer::RendererExportPlyResult)exportPlyAtPath:(NSString*)path format:(uint32_t)format;
- (void)setViewMode:(mesh2splat::renderer::RenderViewMode)mode;
- (void)setGaussianVisualizationMode:(mesh2splat::renderer::GaussianVisualizationMode)mode;
- (void)setGaussianScale:(float)scale;
- (float)gaussianScale;
- (BOOL)setConversionSamplesPerTriangle:(uint32_t)samplesPerTriangle;
- (mesh2splat::renderer::RendererModeResult)applyRenderSettings:
    (const mesh2splat::core::RenderSettingsSnapshot&)settings;
- (void)resizeDrawableToSize:(CGSize)size backingScale:(float)backingScale;
- (void)handleInputEvent:(const mesh2splat::renderer::RendererInputEvent&)event;
- (void)resetFrameClock;
- (NSString*)rendererStatusTitle;
- (NSString*)rendererDiagnostic;
- (NSString*)loadedMeshPath;
- (BOOL)isConvertingGaussians;
- (uint32_t)convertedGaussianCount;
- (mesh2splat::macos::MacBridgeRendererStatusSummary)rendererStatusSummaryWithDrawableWidth:(uint32_t)drawableWidth
                                                                              drawableHeight:(uint32_t)drawableHeight
                                                                                backingScale:(float)backingScale
                                                                           diagnosticOverride:(NSString*)diagnosticOverride;
- (mesh2splat::macos::MacBridgeActionResult)startConversionWithSamplesPerTriangle:(uint32_t)samplesPerTriangle;

@end

@implementation Mesh2SplatMetalViewDelegate {
    std::unique_ptr<mesh2splat::renderer::Renderer> _renderer;
    __weak Mesh2SplatMetalView* _view;
    CFTimeInterval _lastFrameTime;
    CFTimeInterval _lastStatusRefreshTime;
    uint64_t _frameIndex;
}

- (instancetype)initWithView:(Mesh2SplatMetalView*)view
{
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _view = view;
    _lastFrameTime = CACurrentMediaTime();
    _lastStatusRefreshTime = _lastFrameTime;
    _frameIndex = 0;
    _renderer = mesh2splat::renderer::createMetalRenderer((__bridge void*)view.device);
    if (_renderer == nullptr) {
        NSLog(@"Failed to create Metal renderer.");
        return nil;
    }
    if (!_renderer->initialize()) {
        const std::string& diagnostic = _renderer->lastDiagnostic();
        if (diagnostic.empty()) {
            NSLog(@"Failed to initialize Metal renderer.");
        } else {
            NSLog(@"Failed to initialize Metal renderer: %s", diagnostic.c_str());
        }
        return nil;
    }

    [self resizeDrawableToSize:view.drawableSize backingScale:backingScaleForView(view)];
    return self;
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size
{
    (void)view;
    [self resizeDrawableToSize:size backingScale:backingScaleForView(view)];

    Mesh2SplatMetalView* owner = _view;
    [owner refreshRendererStatus];
}

- (void)drawInMTKView:(MTKView*)view
{
    id<CAMetalDrawable> drawable = view.currentDrawable;
    MTLRenderPassDescriptor* descriptor = view.currentRenderPassDescriptor;
    if (drawable == nil || descriptor == nil || _renderer == nullptr) {
        return;
    }

    Mesh2SplatMetalView* owner = _view;
    if (owner == nil) {
        return;
    }

    const CFTimeInterval now = CACurrentMediaTime();
    const double deltaTime = std::min(static_cast<double>(now - _lastFrameTime), 1.0 / 15.0);
    _lastFrameTime = now;

    mesh2splat::renderer::RendererInputEvent tickEvent;
    tickEvent.type = mesh2splat::renderer::RendererInputEventType::FrameTick;
    tickEvent.action = mesh2splat::renderer::RendererInputAction::Tick;
    tickEvent.width = static_cast<uint32_t>(std::max<CGFloat>(1.0, std::round(view.drawableSize.width)));
    tickEvent.height = static_cast<uint32_t>(std::max<CGFloat>(1.0, std::round(view.drawableSize.height)));
    tickEvent.backingScale = backingScaleForView(view);
    tickEvent.deltaTimeSeconds = deltaTime;
    tickEvent.frameIndex = _frameIndex;
    _renderer->handleInputEvent(tickEvent);

    mesh2splat::renderer::RendererFrameTick frame;
    frame.renderPassDescriptor = (__bridge void*)descriptor;
    frame.drawable = (__bridge void*)drawable;
    frame.inputState = [owner inputState];
    frame.inputState.setFrameDeltaSeconds(deltaTime);
    frame.inputState.setViewportSize(tickEvent.width, tickEvent.height);
    frame.deltaTimeSeconds = deltaTime;
    frame.frameIndex = _frameIndex++;
    _renderer->tickFrame(frame);
    [owner beginInputFrame];

    if (now - _lastStatusRefreshTime > 0.5) {
        _lastStatusRefreshTime = now;
        [owner refreshRendererStatus];
    }
}

- (BOOL)loadMeshAtPath:(NSString*)path
{
    if (_renderer == nullptr || path == nil || path.UTF8String == nullptr) {
        return NO;
    }

    mesh2splat::renderer::RendererSceneLoadRequest request;
    request.filePath = std::string(path.UTF8String);
    request.kind = mesh2splat::renderer::RendererSceneKind::Auto;
    request.replaceCurrentScene = true;
    const mesh2splat::renderer::RendererSceneLoadResult result = _renderer->loadScene(request);
    return result.loaded ? YES : NO;
}

- (mesh2splat::renderer::RendererExportPlyResult)exportPlyAtPath:(NSString*)path
{
    return [self exportPlyAtPath:path format:0];
}

- (mesh2splat::renderer::RendererExportPlyResult)exportPlyAtPath:(NSString*)path format:(uint32_t)format
{
    mesh2splat::renderer::RendererExportPlyResult result;
    if (_renderer == nullptr) {
        result.diagnostic = "Renderer is not initialized.";
        return result;
    }
    if (path == nil || path.UTF8String == nullptr) {
        result.diagnostic = "PLY export file path is empty.";
        return result;
    }

    mesh2splat::renderer::RendererExportPlyRequest request;
    request.filePath = std::string(path.UTF8String);
    request.format = format;
    return _renderer->exportPly(request);
}

- (void)setViewMode:(mesh2splat::renderer::RenderViewMode)mode
{
    if (_renderer != nullptr) {
        _renderer->setViewMode(mode);
    }
}

- (void)setGaussianVisualizationMode:(mesh2splat::renderer::GaussianVisualizationMode)mode
{
    if (_renderer != nullptr) {
        _renderer->setGaussianVisualizationMode(mode);
    }
}

- (void)setGaussianScale:(float)scale
{
    if (_renderer != nullptr) {
        _renderer->setGaussianScale(scale);
    }
}

- (float)gaussianScale
{
    return _renderer == nullptr ? 1.0f : _renderer->gaussianScale();
}

- (BOOL)setConversionSamplesPerTriangle:(uint32_t)samplesPerTriangle
{
    return _renderer != nullptr && _renderer->setConversionSamplesPerTriangle(samplesPerTriangle) ? YES : NO;
}

- (mesh2splat::renderer::RendererModeResult)applyRenderSettings:
    (const mesh2splat::core::RenderSettingsSnapshot&)settings
{
    mesh2splat::renderer::RendererModeResult result;
    if (_renderer == nullptr) {
        result.diagnostic = "Renderer is not initialized.";
        return result;
    }

    mesh2splat::renderer::RendererModeRequest request;
    request.viewMode = rendererViewModeFromRenderMode(
        static_cast<NSInteger>(settings.mode),
        settings.meshRenderingEnabled,
        settings.gaussianRenderingEnabled);
    request.gaussianVisualizationMode =
        gaussianVisualizationModeFromRenderMode(static_cast<NSInteger>(settings.mode));
    request.gaussianScale = settings.gaussianScale;
    request.exposure = settings.exposure;
    request.gamma = settings.gamma;
    request.backgroundBrightness = settings.backgroundBrightness;
    request.lightingEnabled = settings.lightingEnabled;
    request.shadowsEnabled = settings.shadowsEnabled;
    request.lightPosition[0] = settings.lightPosition[0];
    request.lightPosition[1] = settings.lightPosition[1];
    request.lightPosition[2] = settings.lightPosition[2];
    request.lightIntensity = settings.lightIntensity;
    request.lightColor[0] = settings.lightColor[0];
    request.lightColor[1] = settings.lightColor[1];
    request.lightColor[2] = settings.lightColor[2];
    request.debugFlags = settings.debugFlags;
    request.depthTestEnabled = settings.depthTestEnabled;
    request.splitScreenEnabled = settings.splitScreenEnabled;
    request.splitScreenPosition = settings.splitScreenPosition;
    request.gaussianSortingEnabled = settings.gaussianSortingEnabled;
    request.meshToGaussianConversionEnabled = settings.meshToGaussianConversionEnabled;
    const bool hadGaussians = _renderer->convertedGaussianCount() > 0;
    const bool wasConverting = _renderer->isConvertingGaussians();
    result = _renderer->setRenderMode(request);

    if (settings.meshToGaussianConversionEnabled && settings.conversionSamplesPerTriangle > 0) {
        const uint32_t requestedSamples = settings.conversionSamplesPerTriangle;
        if (requestedSamples != _renderer->conversionSamplesPerTriangle()) {
            _renderer->setConversionSamplesPerTriangle(requestedSamples);
        } else if (!hadGaussians && !wasConverting && _renderer->diagnostics().hasScene) {
            mesh2splat::renderer::RendererConversionRequest conversionRequest;
            conversionRequest.samplesPerTriangle = requestedSamples;
            conversionRequest.forceRebuild = true;
            _renderer->startConversion(conversionRequest);
        }
    }
    return result;
}

- (void)resizeDrawableToSize:(CGSize)size backingScale:(float)backingScale
{
    if (_renderer == nullptr) {
        return;
    }

    const uint32_t width = static_cast<uint32_t>(std::max<CGFloat>(1.0, std::round(size.width)));
    const uint32_t height = static_cast<uint32_t>(std::max<CGFloat>(1.0, std::round(size.height)));
    mesh2splat::renderer::RendererResizeRequest request;
    request.width = width;
    request.height = height;
    request.backingScale = backingScale > 0.0f ? backingScale : 1.0f;
    _renderer->resize(request);

    mesh2splat::renderer::RendererInputEvent event;
    event.type = mesh2splat::renderer::RendererInputEventType::Resize;
    event.action = mesh2splat::renderer::RendererInputAction::Change;
    event.width = width;
    event.height = height;
    event.backingScale = request.backingScale;
    _renderer->handleInputEvent(event);
}

- (void)handleInputEvent:(const mesh2splat::renderer::RendererInputEvent&)event
{
    if (_renderer != nullptr) {
        _renderer->handleInputEvent(event);
    }
}

- (void)resetFrameClock
{
    _lastFrameTime = CACurrentMediaTime();
    _frameIndex = 0;
}

- (NSString*)rendererStatusTitle
{
    if (_renderer == nullptr) {
        return @"Mesh2Splat Metal";
    }

    const mesh2splat::renderer::RendererDiagnostics diagnostics = _renderer->diagnostics();
    NSString* mode = @"Combined";
    switch (diagnostics.viewMode) {
    case mesh2splat::renderer::RenderViewMode::Combined:
        mode = @"Combined";
        break;
    case mesh2splat::renderer::RenderViewMode::MeshOnly:
        mode = @"Mesh";
        break;
    case mesh2splat::renderer::RenderViewMode::GaussianOnly:
        mode = @"Gaussians";
        break;
    }

    NSString* assetName = @"Preview";
    const std::string& displayName = diagnostics.loadedScene.displayName;
    if (!displayName.empty()) {
        assetName = stringFromUtf8(displayName);
    } else if (!diagnostics.loadedScenePath.empty()) {
        assetName = [stringFromUtf8(diagnostics.loadedScenePath) lastPathComponent];
    }

    const mesh2splat::renderer::RendererStats& stats = diagnostics.stats;
    NSString* conversionState = diagnostics.converting ? @"converting" : @"ready";

    return [NSString stringWithFormat:@"Mesh2Splat Metal - %@ - %@ - %@ - %u gaussians - scale x%.2f - quality %ux - %.1f/%.1f ms",
                                      truncatedTitleComponent(assetName, 44),
                                      mode,
                                      conversionState,
                                      diagnostics.convertedGaussianCount,
                                      diagnostics.gaussianScale,
                                      diagnostics.conversionSamplesPerTriangle,
                                      stats.lastFrameCpuEncodeMs,
                                      stats.lastFrameGpuMs];
}

- (NSString*)rendererDiagnostic
{
    if (_renderer == nullptr) {
        return @"Renderer is not initialized.";
    }

    const std::string& diagnostic = _renderer->lastDiagnostic();
    return diagnostic.empty() ? @"" : stringFromUtf8(diagnostic);
}

- (NSString*)loadedMeshPath
{
    if (_renderer == nullptr) {
        return @"";
    }

    return stringFromUtf8(_renderer->loadedMeshPath());
}

- (BOOL)isConvertingGaussians
{
    return _renderer != nullptr && _renderer->isConvertingGaussians();
}

- (uint32_t)convertedGaussianCount
{
    return _renderer == nullptr ? 0 : _renderer->convertedGaussianCount();
}

- (mesh2splat::macos::MacBridgeRendererStatusSummary)rendererStatusSummaryWithDrawableWidth:(uint32_t)drawableWidth
                                                                              drawableHeight:(uint32_t)drawableHeight
                                                                                backingScale:(float)backingScale
                                                                           diagnosticOverride:(NSString*)diagnosticOverride
{
    mesh2splat::macos::MacBridgeRendererStatusSummary summary;
    summary.drawableWidth = drawableWidth;
    summary.drawableHeight = drawableHeight;
    summary.backingScale = backingScale > 0.0f ? backingScale : 1.0f;

    if (_renderer == nullptr) {
        summary.runtimeState = mesh2splat::macos::MacBridgeRendererRuntimeState::Failed;
        summary.diagnosticSeverity = mesh2splat::macos::MacBridgeDiagnosticSeverity::Error;
        summary.statusText = "Renderer unavailable";
        summary.diagnosticMessage = "Renderer is not initialized.";
        return summary;
    }

    const mesh2splat::renderer::RendererDiagnostics diagnostics = _renderer->diagnostics();
    const mesh2splat::renderer::RendererStats& stats = diagnostics.stats;
    const mesh2splat::renderer::RendererSceneCounts& sceneCounts = diagnostics.sceneCounts;
    const mesh2splat::renderer::RendererRenderSettingsSummary& renderSettings = diagnostics.renderSettings;
    summary.runtimeState = macRuntimeStateFromRenderer(diagnostics.state);
    summary.diagnosticSeverity = macSeverityFromRenderer(diagnostics.severity);
    summary.viewMode = macViewModeFromRenderer(renderSettings.viewMode);
    summary.gaussianVisualizationMode = static_cast<std::uint32_t>(renderSettings.gaussianVisualizationMode);
    summary.backend.runtimeState = summary.runtimeState;
    summary.backend.supported = true;
    summary.backend.initialized = true;
    summary.backend.shaderLibraryReady = true;
    summary.backend.pipelineCacheReady = true;
    summary.loadedScenePath = diagnostics.loadedScenePath.empty()
        ? diagnostics.assetSession.sourcePath
        : diagnostics.loadedScenePath;
    summary.loadedSceneDisplayName = diagnostics.loadedScene.displayName.empty()
        ? diagnostics.assetSession.displayName
        : diagnostics.loadedScene.displayName;
    summary.exportPath = diagnostics.assetSession.exportPath;
    summary.diagnosticMessage = diagnosticOverride.length > 0 ?
        std::string(diagnosticOverride.UTF8String) :
        diagnostics.message;
    summary.lastError = diagnostics.lastError;
    summary.convertedGaussianCount = diagnostics.convertedGaussianCount;
    summary.gaussianScale = renderSettings.gaussianScale;
    summary.exposure = renderSettings.exposure;
    summary.gamma = renderSettings.gamma;
    summary.backgroundBrightness = renderSettings.backgroundBrightness;
    summary.lightingEnabled = renderSettings.lightingEnabled;
    summary.shadowsEnabled = renderSettings.shadowsEnabled;
    summary.lightPositionX = renderSettings.lightPosition[0];
    summary.lightPositionY = renderSettings.lightPosition[1];
    summary.lightPositionZ = renderSettings.lightPosition[2];
    summary.lightIntensity = renderSettings.lightIntensity;
    summary.lightColorRed = renderSettings.lightColor[0];
    summary.lightColorGreen = renderSettings.lightColor[1];
    summary.lightColorBlue = renderSettings.lightColor[2];
    summary.debugFlags = renderSettings.debugFlags;
    summary.depthTestEnabled = renderSettings.depthTestEnabled;
    summary.splitScreenEnabled = renderSettings.splitScreenEnabled;
    summary.splitScreenPosition = renderSettings.splitScreenPosition;
    summary.conversionProgress = diagnostics.progress;
    summary.conversionSamplesPerTriangle = renderSettings.conversionSamplesPerTriangle;
    summary.submittedConversionCount = stats.submittedConversionCount;
    summary.completedConversionCount = stats.completedConversionCount;
    summary.failedConversionCount = stats.failedConversionCount;
    summary.submittedFrameCount = stats.submittedFrameCount;
    summary.completedFrameCount = stats.completedFrameCount;
    summary.failedFrameCount = stats.failedFrameCount;
    summary.lastFrameCpuEncodeMs = stats.lastFrameCpuEncodeMs;
    summary.averageFrameCpuEncodeMs = stats.averageFrameCpuEncodeMs;
    summary.lastFrameGpuMs = stats.lastFrameGpuMs;
    summary.averageFrameGpuMs = stats.averageFrameGpuMs;
    summary.lastConversionCpuSubmitMs = stats.lastConversionCpuSubmitMs;
    summary.averageConversionCpuSubmitMs = stats.averageConversionCpuSubmitMs;
    summary.lastConversionGpuMs = stats.lastConversionGpuMs;
    summary.averageConversionGpuMs = stats.averageConversionGpuMs;
    summary.frameUniformResourceBytes = stats.frameUniformResourceBytes;
    summary.sceneResourceBytes = stats.sceneResourceBytes;
    summary.gaussianResourceBytes = stats.gaussianResourceBytes;
    summary.gaussianSortResourceBytes = stats.gaussianSortResourceBytes;
    summary.shadowResourceBytes = stats.shadowResourceBytes;
    summary.pendingConversionResourceBytes = stats.pendingConversionResourceBytes;
    summary.trackedResourceBytes = stats.trackedResourceBytes;
    summary.meshCount = static_cast<std::uint32_t>(std::min<std::uint64_t>(
        sceneCounts.meshCount,
        std::numeric_limits<std::uint32_t>::max()));
    summary.materialCount = static_cast<std::uint32_t>(std::min<std::uint64_t>(
        sceneCounts.materialCount,
        std::numeric_limits<std::uint32_t>::max()));
    summary.textureCount = static_cast<std::uint32_t>(std::min<std::uint64_t>(
        sceneCounts.textureCount,
        std::numeric_limits<std::uint32_t>::max()));
    summary.hasScene = diagnostics.hasScene;
    summary.hasGaussians = diagnostics.hasGaussians;
    summary.hasVisibleMesh = diagnostics.hasVisibleMesh;
    summary.isConverting = diagnostics.converting;
    summary.meshRenderingEnabled = renderSettings.meshRenderingEnabled;
    summary.gaussianRenderingEnabled = renderSettings.gaussianRenderingEnabled;
    summary.gaussianSortingEnabled = renderSettings.gaussianSortingEnabled;
    summary.meshToGaussianConversionEnabled = renderSettings.meshToGaussianConversionEnabled;
    summary.exportMatchesCurrentConversion = diagnostics.assetSession.exportMatchesCurrentConversion;
    const bool rendererFailed =
        diagnostics.state == mesh2splat::renderer::RendererRuntimeState::Failed ||
        diagnostics.severity == mesh2splat::renderer::RendererDiagnosticSeverity::Error;
    const bool rendererExporting =
        diagnostics.state == mesh2splat::renderer::RendererRuntimeState::Exporting ||
        diagnostics.assetSession.exportState == mesh2splat::renderer::RendererAssetExportState::Pending ||
        diagnostics.assetSession.exportState == mesh2splat::renderer::RendererAssetExportState::Exporting;
    const bool rendererLoading =
        diagnostics.state == mesh2splat::renderer::RendererRuntimeState::Loading;
    summary.canImportScene = !rendererLoading && !rendererExporting && !diagnostics.converting;
    summary.canStartConversion =
        !rendererFailed &&
        !rendererExporting &&
        !diagnostics.converting &&
        diagnostics.hasScene &&
        diagnostics.hasVisibleMesh;
    summary.canExportGaussians =
        !rendererFailed &&
        !rendererExporting &&
        !diagnostics.converting &&
        diagnostics.hasGaussians;
    summary.lastFrameRenderedMesh = stats.lastFrameRenderedMesh;
    summary.lastFrameRenderedGaussians = stats.lastFrameRenderedGaussians;
    summary.lastFrameSortedGaussians = stats.lastFrameSortedGaussians;
    summary.frameTiming.submittedFrameCount = stats.submittedFrameCount;
    summary.frameTiming.completedFrameCount = stats.completedFrameCount;
    summary.frameTiming.failedFrameCount = stats.failedFrameCount;
    summary.frameTiming.lastCpuEncodeMs = stats.lastFrameCpuEncodeMs;
    summary.frameTiming.averageCpuEncodeMs = stats.averageFrameCpuEncodeMs;
    summary.frameTiming.lastGpuMs = stats.lastFrameGpuMs;
    summary.frameTiming.averageGpuMs = stats.averageFrameGpuMs;
    summary.frameTiming.lastRenderedMesh = stats.lastFrameRenderedMesh;
    summary.frameTiming.lastRenderedGaussians = stats.lastFrameRenderedGaussians;
    summary.frameTiming.lastSortedGaussians = stats.lastFrameSortedGaussians;
    summary.resources.frameUniformBytes = stats.frameUniformResourceBytes;
    summary.resources.sceneBytes = stats.sceneResourceBytes;
    summary.resources.gaussianBytes = stats.gaussianResourceBytes;
    summary.resources.gaussianSortBytes = stats.gaussianSortResourceBytes;
    summary.resources.shadowBytes = stats.shadowResourceBytes;
    summary.resources.pendingConversionBytes = stats.pendingConversionResourceBytes;
    summary.resources.trackedBytes = stats.trackedResourceBytes;
    summary.resources.meshCount = summary.meshCount;
    summary.resources.materialCount = summary.materialCount;
    summary.resources.textureCount = summary.textureCount;
    summary.resources.gaussianCount = diagnostics.convertedGaussianCount;
    summary.conversion.active = diagnostics.converting;
    summary.conversion.progress = diagnostics.progress;
    summary.conversion.samplesPerTriangle = diagnostics.conversionSamplesPerTriangle;
    summary.conversion.convertedGaussianCount = diagnostics.convertedGaussianCount;
    summary.conversion.submittedConversionCount = stats.submittedConversionCount;
    summary.conversion.completedConversionCount = stats.completedConversionCount;
    summary.conversion.failedConversionCount = stats.failedConversionCount;
    summary.conversion.lastCpuSubmitMs = stats.lastConversionCpuSubmitMs;
    summary.conversion.averageCpuSubmitMs = stats.averageConversionCpuSubmitMs;
    summary.conversion.lastGpuMs = stats.lastConversionGpuMs;
    summary.conversion.averageGpuMs = stats.averageConversionGpuMs;
    summary.diagnostics.severity = summary.diagnosticSeverity;
    summary.diagnostics.message = summary.diagnosticMessage;
    summary.diagnostics.lastError = summary.lastError;

    summary.statusText = diagnostics.statusText.empty() ? diagnostics.message : diagnostics.statusText;
    if (summary.statusText.empty()) {
        NSString* title = [self rendererStatusTitle];
        summary.statusText = title.length > 0 ? std::string(title.UTF8String) : std::string();
    }
    return summary;
}

- (mesh2splat::macos::MacBridgeActionResult)startConversionWithSamplesPerTriangle:(uint32_t)samplesPerTriangle
{
    mesh2splat::macos::MacBridgeActionResult actionResult;
    if (_renderer == nullptr) {
        actionResult.message = "Renderer is not initialized.";
        actionResult.status.runtimeState = mesh2splat::macos::MacBridgeRendererRuntimeState::Failed;
        actionResult.status.diagnosticSeverity = mesh2splat::macos::MacBridgeDiagnosticSeverity::Error;
        actionResult.status.diagnosticMessage = actionResult.message;
        return actionResult;
    }

    mesh2splat::renderer::RendererConversionRequest request;
    request.samplesPerTriangle = samplesPerTriangle;
    request.forceRebuild = true;
    const mesh2splat::renderer::RendererConversionResult conversionResult = _renderer->startConversion(request);
    actionResult.accepted = conversionResult.accepted;
    actionResult.completed = conversionResult.started || conversionResult.convertedGaussianCount > 0;
    actionResult.message = conversionResult.diagnostic;
    actionResult.status = [self rendererStatusSummaryWithDrawableWidth:0
                                                        drawableHeight:0
                                                          backingScale:1.0f
                                                     diagnosticOverride:stringFromUtf8(conversionResult.diagnostic)];
    return actionResult;
}

@end

@implementation Mesh2SplatMetalView {
    mesh2splat::core::InputState _inputState;
    NSInteger _bridgeRenderMode;
    double _bridgeExposure;
    double _bridgeGamma;
    double _bridgeBackgroundBrightness;
    BOOL _bridgeSortingEnabled;
    BOOL _bridgeMeshRenderingEnabled;
    BOOL _bridgeGaussianRenderingEnabled;
    BOOL _bridgeConversionEnabled;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    self = [super initWithFrame:frameRect device:device];
    if (self == nil) {
        return nil;
    }

    if (device == nil) {
        NSLog(@"Metal is not supported on this Mac.");
        return self;
    }

    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    self.clearColor = MTLClearColorMake(0.03, 0.04, 0.05, 1.0);
    _bridgeRenderMode = 0;
    _bridgeExposure = 1.0;
    _bridgeGamma = 2.2;
    _bridgeBackgroundBrightness = 0.04;
    _bridgeSortingEnabled = YES;
    _bridgeMeshRenderingEnabled = YES;
    _bridgeGaussianRenderingEnabled = YES;
    _bridgeConversionEnabled = YES;
    self.preferredFramesPerSecond = 60;
    self.enableSetNeedsDisplay = NO;
    self.paused = NO;
    self.framebufferOnly = YES;
    self.autoResizeDrawable = NO;
    self.lastDiagnosticMessage = @"Drop or open a .glb, .gltf, or .ply scene.";
    self.lastImportStatus = @"Import: waiting";
    self.lastConversionStatus = @"Conversion: idle";
    self.lastExportStatus = @"Export: not ready";
    [self registerForDraggedTypes:@[ NSPasteboardTypeFileURL ]];
    [self configureStatusLabel];

    self.meshDelegate = [[Mesh2SplatMetalViewDelegate alloc] initWithView:self];
    self.delegate = self.meshDelegate;
    return self;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (NSSize)intrinsicContentSize
{
    // SwiftUI hosts this view inside a flexible viewport; do not fight the
    // layout engine with a fixed intrinsic size, otherwise MTKView reports an
    // unbounded preferred size and SwiftUI enters an endless layout loop that
    // starves frame drawing.
    return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self updateRenderLoopState];
    [self updateDrawableSizeForBackingScale];
    [self.meshDelegate resetFrameClock];
    [self.window makeFirstResponder:self];
    [self refreshRendererStatus];
}

- (void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    [self updateDrawableSizeForBackingScale];
    [self refreshRendererStatus];
}

- (void)layout
{
    [super layout];

    const CGFloat horizontalInset = 14.0;
    const CGFloat bottomInset = 12.0;
    const CGFloat height = 30.0;
    self.statusLabel.frame = NSMakeRect(
        horizontalInset,
        bottomInset,
        std::max<CGFloat>(0.0, NSWidth(self.bounds) - horizontalInset * 2.0),
        height);
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [self updateDrawableSizeForBackingScale];
    [self refreshRendererStatus];
}

- (void)setBoundsSize:(NSSize)newSize
{
    [super setBoundsSize:newSize];
    [self updateDrawableSizeForBackingScale];
    [self refreshRendererStatus];
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];

    if (self.pointerTrackingArea != nil) {
        [self removeTrackingArea:self.pointerTrackingArea];
    }

    NSTrackingAreaOptions options = NSTrackingMouseMoved |
                                    NSTrackingActiveInKeyWindow |
                                    NSTrackingInVisibleRect |
                                    NSTrackingEnabledDuringMouseDrag;
    self.pointerTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                            options:options
                                                              owner:self
                                                           userInfo:nil];
    [self addTrackingArea:self.pointerTrackingArea];
}

- (void)beginInputFrame
{
    _inputState.beginFrame();
}

- (const mesh2splat::core::InputState&)inputState
{
    return _inputState;
}

- (void)openMeshDocument
{
    self.lastImportStatus = @"Import: choosing file";
    [self refreshRendererStatus];

    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedContentTypes = meshContentTypes();

    __weak Mesh2SplatMetalView* weakSelf = self;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        Mesh2SplatMetalView* strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (response != NSModalResponseOK) {
            strongSelf.lastImportStatus = @"Import: cancelled";
            [strongSelf refreshRendererStatus];
            return;
        }

        NSURL* url = panel.URL;
        if (![strongSelf openMeshAtURL:url]) {
            NSBeep();
        }
    }];
}

- (void)exportGaussianPlyDocument
{
    if ([self.meshDelegate isConvertingGaussians]) {
        self.lastExportStatus = @"Export: waiting for conversion";
        self.lastDiagnosticMessage = @"Wait for conversion to finish before exporting.";
        [self refreshRendererStatus];
        NSBeep();
        return;
    }

    if ([self.meshDelegate convertedGaussianCount] == 0) {
        self.lastExportStatus = @"Export: no gaussians";
        self.lastDiagnosticMessage = @"Load a mesh and wait for converted gaussians before exporting.";
        [self refreshRendererStatus];
        NSBeep();
        return;
    }

    self.lastExportStatus = @"Export: choosing destination";
    [self refreshRendererStatus];

    NSSavePanel* panel = [NSSavePanel savePanel];
    panel.canCreateDirectories = YES;
    panel.allowedContentTypes = plyContentTypes();
    panel.nameFieldStringValue = defaultGaussianExportName([self.meshDelegate loadedMeshPath]);
    panel.title = @"Export Gaussian PLY";
    panel.message = @"Choose where to save the converted gaussian point cloud.";

    __weak Mesh2SplatMetalView* weakSelf = self;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        Mesh2SplatMetalView* strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (response != NSModalResponseOK) {
            strongSelf.lastExportStatus = @"Export: cancelled";
            [strongSelf refreshRendererStatus];
            return;
        }

        if (![strongSelf exportGaussianPlyAtURL:panel.URL]) {
            NSBeep();
        }
    }];
}

- (void)configureStatusLabel
{
    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = YES;
    self.statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.statusLabel.drawsBackground = YES;
    self.statusLabel.backgroundColor = [NSColor colorWithWhite:0.04 alpha:0.82];
    self.statusLabel.textColor = NSColor.controlTextColor;
    self.statusLabel.font = [NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightMedium];
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.statusLabel.alignment = NSTextAlignmentCenter;
    self.statusLabel.bordered = NO;
    self.statusLabel.editable = NO;
    self.statusLabel.selectable = NO;
    self.statusLabel.wantsLayer = YES;
    self.statusLabel.layer.cornerRadius = 6.0;
    self.statusLabel.layer.masksToBounds = YES;
    [self addSubview:self.statusLabel];
}

- (void)updateStatusLabelWithTitle:(NSString*)title
{
    if (self.statusLabel == nil) {
        return;
    }

    NSString* diagnostic = self.lastDiagnosticMessage.length > 0 ? self.lastDiagnosticMessage : [self.meshDelegate rendererDiagnostic];
    NSString* status = [NSString stringWithFormat:@"%@   %@   %@   %@",
                                                  self.lastImportStatus ?: @"Import: idle",
                                                  self.lastConversionStatus ?: @"Conversion: idle",
                                                  self.lastExportStatus ?: @"Export: idle",
                                                  title ?: @"Mesh2Splat Metal"];
    if (diagnostic.length > 0) {
        status = [status stringByAppendingFormat:@"   %@", diagnostic];
    }
    self.statusLabel.stringValue = status;
}

- (void)updateDrawableSizeForBackingScale
{
    if (self.window == nil || self.device == nil) {
        return;
    }

    NSRect backingBounds = [self convertRectToBacking:self.bounds];
    CGSize drawableSize = CGSizeMake(
        std::max<CGFloat>(1.0, std::round(NSWidth(backingBounds))),
        std::max<CGFloat>(1.0, std::round(NSHeight(backingBounds))));
    self.drawableSize = drawableSize;
    [self.meshDelegate resizeDrawableToSize:drawableSize backingScale:backingScaleForView(self)];
}

- (void)dispatchInputEvent:(const mesh2splat::renderer::RendererInputEvent&)event
{
    [self.meshDelegate handleInputEvent:event];
}

- (void)updateRenderLoopState
{
    self.paused = self.window == nil;
}

- (BOOL)openMeshAtURL:(NSURL*)url
{
    if (!meshURLLooksSupported(url)) {
        self.lastDiagnosticMessage = @"Choose a .glb, .gltf, or .ply scene file.";
        [self refreshRendererStatus];
        return NO;
    }

    const BOOL loadingGaussianPly = urlLooksLikeGaussianPly(url);
    const BOOL hasSecurityScope = [url startAccessingSecurityScopedResource];
    const BOOL loaded = [self.meshDelegate loadMeshAtPath:url.path];
    if (hasSecurityScope) {
        [url stopAccessingSecurityScopedResource];
    }

    if (!loaded) {
        NSString* rendererDiagnostic = [self.meshDelegate rendererDiagnostic];
        self.lastDiagnosticMessage =
            rendererDiagnostic.length > 0 ? rendererDiagnostic : [NSString stringWithFormat:@"Could not open %@.", url.lastPathComponent];
        self.lastImportStatus = @"Import: failed";
        self.lastConversionStatus = @"Conversion: idle";
        self.lastExportStatus = @"Export: not ready";
        [self refreshRendererStatus];
        return NO;
    }

    self.lastDiagnosticMessage = nil;
    self.lastImportStatus = [NSString stringWithFormat:@"Import: loaded %@", url.lastPathComponent];
    if (loadingGaussianPly) {
        self.lastConversionStatus = [NSString stringWithFormat:@"Conversion: %u gaussians", [self.meshDelegate convertedGaussianCount]];
        self.lastExportStatus = @"Export: ready";
    } else {
        self.lastConversionStatus = @"Conversion: running";
        self.lastExportStatus = @"Export: waiting";
    }
    [self.meshDelegate resetFrameClock];
    [self refreshRendererStatus];
    return YES;
}

- (BOOL)exportGaussianPlyAtURL:(NSURL*)url
{
    return [self exportGaussianPlyAtURL:url format:0];
}

- (BOOL)exportGaussianPlyAtURL:(NSURL*)url format:(uint32_t)format
{
    if (url == nil || !url.isFileURL) {
        self.lastExportStatus = @"Export: failed";
        self.lastDiagnosticMessage = @"Choose a valid .ply export path.";
        [self refreshRendererStatus];
        return NO;
    }

    self.lastExportStatus = [NSString stringWithFormat:@"Export: writing %@", url.lastPathComponent];
    [self refreshRendererStatus];

    const BOOL hasSecurityScope = [url startAccessingSecurityScopedResource];
    mesh2splat::renderer::RendererExportPlyResult result = [self.meshDelegate exportPlyAtPath:url.path format:format];
    if (hasSecurityScope) {
        [url stopAccessingSecurityScopedResource];
    }

    if (!result.exported) {
        self.lastDiagnosticMessage = result.diagnostic.empty() ?
            @"Could not export Gaussian PLY." :
            stringFromUtf8(result.diagnostic);
        self.lastExportStatus = @"Export: failed";
        [self refreshRendererStatus];
        return NO;
    }

    self.lastDiagnosticMessage = [NSString stringWithFormat:@"Exported %llu gaussians to %@.",
                                                            result.writtenCount,
                                                            url.lastPathComponent];
    self.lastExportStatus = [NSString stringWithFormat:@"Export: saved %@", url.lastPathComponent];
    [self refreshRendererStatus];
    return YES;
}

- (void)refreshRendererStatus
{
    if (self.window == nil) {
        return;
    }

    NSString* title = [self.meshDelegate rendererStatusTitle];
    NSRect backingBounds = [self convertRectToBacking:self.bounds];
    CGFloat scale = self.window.backingScaleFactor;
    if (scale <= 0.0) {
        NSScreen* screen = self.window.screen;
        scale = screen == nil ? 1.0 : screen.backingScaleFactor;
    }
    title = [title stringByAppendingFormat:@" - %.0fx%.0f @%.1fx",
                                             std::round(NSWidth(backingBounds)),
                                             std::round(NSHeight(backingBounds)),
                                             scale];

    NSString* rendererDiagnostic = [self.meshDelegate rendererDiagnostic];
    NSString* diagnostic = self.lastDiagnosticMessage.length > 0 ? self.lastDiagnosticMessage : rendererDiagnostic;
    if (diagnostic.length > 0) {
        title = [title stringByAppendingFormat:@" - %@", truncatedTitleComponent(diagnostic, 80)];
    }

    self.window.title = title;
    const BOOL isConverting = [self.meshDelegate isConvertingGaussians];
    const uint32_t gaussianCount = [self.meshDelegate convertedGaussianCount];
    self.lastConversionStatus = isConverting ?
        @"Conversion: running" :
        [NSString stringWithFormat:@"Conversion: %u gaussians", gaussianCount];
    if (gaussianCount > 0 && !isConverting && [self.lastExportStatus isEqualToString:@"Export: waiting"]) {
        self.lastExportStatus = @"Export: ready";
    }
    [self updateStatusLabelWithTitle:title];
}

- (void)applyRenderMode:(NSInteger)renderMode
              splatSize:(double)splatSize
               exposure:(double)exposure
                  gamma:(double)gamma
   backgroundBrightness:(double)backgroundBrightness
conversionSamplesPerTriangle:(NSInteger)conversionSamplesPerTriangle
         sortingEnabled:(BOOL)sortingEnabled
   meshRenderingEnabled:(BOOL)meshRenderingEnabled
gaussianRenderingEnabled:(BOOL)gaussianRenderingEnabled
      conversionEnabled:(BOOL)conversionEnabled
       depthTestEnabled:(BOOL)depthTestEnabled
     splitScreenEnabled:(BOOL)splitScreenEnabled
    splitScreenPosition:(double)splitScreenPosition
        lightingEnabled:(BOOL)lightingEnabled
         shadowsEnabled:(BOOL)shadowsEnabled
         lightPositionX:(double)lightPositionX
         lightPositionY:(double)lightPositionY
         lightPositionZ:(double)lightPositionZ
         lightIntensity:(double)lightIntensity
          lightColorRed:(double)lightColorRed
        lightColorGreen:(double)lightColorGreen
         lightColorBlue:(double)lightColorBlue
             debugFlags:(uint32_t)debugFlags
{
    const mesh2splat::core::RenderSettingsSnapshot settings =
        renderSettingsSnapshotFromBridge(
            renderMode,
            splatSize,
            exposure,
            gamma,
            backgroundBrightness,
            conversionSamplesPerTriangle,
            sortingEnabled,
            meshRenderingEnabled,
            gaussianRenderingEnabled,
            conversionEnabled,
            depthTestEnabled,
            splitScreenEnabled,
            splitScreenPosition,
            lightingEnabled,
            shadowsEnabled,
            lightPositionX,
            lightPositionY,
            lightPositionZ,
            lightIntensity,
            lightColorRed,
            lightColorGreen,
            lightColorBlue,
            debugFlags);

    _bridgeRenderMode = static_cast<NSInteger>(settings.mode);
    _bridgeExposure = settings.exposure;
    _bridgeGamma = settings.gamma;
    _bridgeBackgroundBrightness = settings.backgroundBrightness;
    _bridgeSortingEnabled = settings.gaussianSortingEnabled;
    _bridgeMeshRenderingEnabled = settings.meshRenderingEnabled;
    _bridgeGaussianRenderingEnabled = settings.gaussianRenderingEnabled;
    _bridgeConversionEnabled = settings.meshToGaussianConversionEnabled;

    [self.meshDelegate applyRenderSettings:settings];

    [self refreshRendererStatus];
}

- (void)setBackgroundColorRed:(double)red green:(double)green blue:(double)blue
{
    const double clampedRed = std::clamp(red, 0.0, 1.0);
    const double clampedGreen = std::clamp(green, 0.0, 1.0);
    const double clampedBlue = std::clamp(blue, 0.0, 1.0);
    self.clearColor = MTLClearColorMake(clampedRed, clampedGreen, clampedBlue, 1.0);
}

- (IBAction)openDocument:(id)sender
{
    (void)sender;
    [self openMeshDocument];
}

- (IBAction)exportDocument:(id)sender
{
    (void)sender;
    [self exportGaussianPlyDocument];
}

- (IBAction)showCombinedView:(id)sender
{
    (void)sender;
    [self.meshDelegate setViewMode:mesh2splat::renderer::RenderViewMode::Combined];
    [self refreshRendererStatus];
}

- (IBAction)showMeshView:(id)sender
{
    (void)sender;
    [self.meshDelegate setViewMode:mesh2splat::renderer::RenderViewMode::MeshOnly];
    [self refreshRendererStatus];
}

- (IBAction)showGaussianView:(id)sender
{
    (void)sender;
    [self.meshDelegate setViewMode:mesh2splat::renderer::RenderViewMode::GaussianOnly];
    [self refreshRendererStatus];
}

- (IBAction)increaseGaussianScale:(id)sender
{
    (void)sender;
    [self.meshDelegate setGaussianScale:[self.meshDelegate gaussianScale] * 1.2f];
    [self refreshRendererStatus];
}

- (IBAction)decreaseGaussianScale:(id)sender
{
    (void)sender;
    [self.meshDelegate setGaussianScale:[self.meshDelegate gaussianScale] / 1.2f];
    [self refreshRendererStatus];
}

- (IBAction)resetGaussianScale:(id)sender
{
    (void)sender;
    [self.meshDelegate setGaussianScale:1.0f];
    [self refreshRendererStatus];
}

- (IBAction)setLowConversionQuality:(id)sender
{
    (void)sender;
    if (![self.meshDelegate setConversionSamplesPerTriangle:1]) {
        NSBeep();
    }
    [self refreshRendererStatus];
}

- (IBAction)setMediumConversionQuality:(id)sender
{
    (void)sender;
    if (![self.meshDelegate setConversionSamplesPerTriangle:4]) {
        NSBeep();
    }
    [self refreshRendererStatus];
}

- (IBAction)setHighConversionQuality:(id)sender
{
    (void)sender;
    if (![self.meshDelegate setConversionSamplesPerTriangle:9]) {
        NSBeep();
    }
    [self refreshRendererStatus];
}

- (NSPoint)updateMousePosition:(NSEvent*)event
{
    NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint backingLocation = [self convertPointToBacking:location];
    _inputState.updateMousePosition(backingLocation.x, backingLocation.y);
    _inputState.setModifiers(rendererModifierMaskFromEvent(event));
    return backingLocation;
}

- (void)mouseMoved:(NSEvent*)event
{
    NSPoint location = [self updateMousePosition:event];
    mesh2splat::renderer::RendererInputEvent inputEvent;
    inputEvent.type = mesh2splat::renderer::RendererInputEventType::MouseMove;
    inputEvent.action = mesh2splat::renderer::RendererInputAction::Move;
    inputEvent.modifiers = rendererModifierMaskFromEvent(event);
    inputEvent.x = location.x;
    inputEvent.y = location.y;
    inputEvent.deltaX = event.deltaX;
    inputEvent.deltaY = event.deltaY;
    [self dispatchInputEvent:inputEvent];
}

- (void)mouseDragged:(NSEvent*)event
{
    [self mouseMoved:event];
}

- (void)rightMouseDragged:(NSEvent*)event
{
    [self mouseMoved:event];
}

- (void)otherMouseDragged:(NSEvent*)event
{
    [self mouseMoved:event];
}

- (void)mouseDown:(NSEvent*)event
{
    NSPoint location = [self updateMousePosition:event];
    _inputState.setMouseButton(0, true);
    mesh2splat::renderer::RendererInputEvent inputEvent;
    inputEvent.type = mesh2splat::renderer::RendererInputEventType::MouseButton;
    inputEvent.action = mesh2splat::renderer::RendererInputAction::Press;
    inputEvent.code = 0;
    inputEvent.modifiers = rendererModifierMaskFromEvent(event);
    inputEvent.x = location.x;
    inputEvent.y = location.y;
    [self dispatchInputEvent:inputEvent];
}

- (void)mouseUp:(NSEvent*)event
{
    NSPoint location = [self updateMousePosition:event];
    _inputState.setMouseButton(0, false);
    mesh2splat::renderer::RendererInputEvent inputEvent;
    inputEvent.type = mesh2splat::renderer::RendererInputEventType::MouseButton;
    inputEvent.action = mesh2splat::renderer::RendererInputAction::Release;
    inputEvent.code = 0;
    inputEvent.modifiers = rendererModifierMaskFromEvent(event);
    inputEvent.x = location.x;
    inputEvent.y = location.y;
    [self dispatchInputEvent:inputEvent];
}

- (void)rightMouseDown:(NSEvent*)event
{
    NSPoint location = [self updateMousePosition:event];
    _inputState.setMouseButton(1, true);
    mesh2splat::renderer::RendererInputEvent inputEvent;
    inputEvent.type = mesh2splat::renderer::RendererInputEventType::MouseButton;
    inputEvent.action = mesh2splat::renderer::RendererInputAction::Press;
    inputEvent.code = 1;
    inputEvent.modifiers = rendererModifierMaskFromEvent(event);
    inputEvent.x = location.x;
    inputEvent.y = location.y;
    [self dispatchInputEvent:inputEvent];
}

- (void)rightMouseUp:(NSEvent*)event
{
    NSPoint location = [self updateMousePosition:event];
    _inputState.setMouseButton(1, false);
    mesh2splat::renderer::RendererInputEvent inputEvent;
    inputEvent.type = mesh2splat::renderer::RendererInputEventType::MouseButton;
    inputEvent.action = mesh2splat::renderer::RendererInputAction::Release;
    inputEvent.code = 1;
    inputEvent.modifiers = rendererModifierMaskFromEvent(event);
    inputEvent.x = location.x;
    inputEvent.y = location.y;
    [self dispatchInputEvent:inputEvent];
}

- (void)otherMouseDown:(NSEvent*)event
{
    NSPoint location = [self updateMousePosition:event];
    _inputState.setMouseButton(2, true);
    mesh2splat::renderer::RendererInputEvent inputEvent;
    inputEvent.type = mesh2splat::renderer::RendererInputEventType::MouseButton;
    inputEvent.action = mesh2splat::renderer::RendererInputAction::Press;
    inputEvent.code = 2;
    inputEvent.modifiers = rendererModifierMaskFromEvent(event);
    inputEvent.x = location.x;
    inputEvent.y = location.y;
    [self dispatchInputEvent:inputEvent];
}

- (void)otherMouseUp:(NSEvent*)event
{
    NSPoint location = [self updateMousePosition:event];
    _inputState.setMouseButton(2, false);
    mesh2splat::renderer::RendererInputEvent inputEvent;
    inputEvent.type = mesh2splat::renderer::RendererInputEventType::MouseButton;
    inputEvent.action = mesh2splat::renderer::RendererInputAction::Release;
    inputEvent.code = 2;
    inputEvent.modifiers = rendererModifierMaskFromEvent(event);
    inputEvent.x = location.x;
    inputEvent.y = location.y;
    [self dispatchInputEvent:inputEvent];
}

- (void)scrollWheel:(NSEvent*)event
{
    _inputState.setModifiers(rendererModifierMaskFromEvent(event));
    _inputState.addScrollDelta(event.scrollingDeltaX, event.scrollingDeltaY);
    mesh2splat::renderer::RendererInputEvent inputEvent;
    inputEvent.type = mesh2splat::renderer::RendererInputEventType::MouseScroll;
    inputEvent.action = mesh2splat::renderer::RendererInputAction::Scroll;
    inputEvent.modifiers = rendererModifierMaskFromEvent(event);
    inputEvent.deltaX = event.scrollingDeltaX;
    inputEvent.deltaY = event.scrollingDeltaY;
    [self dispatchInputEvent:inputEvent];
}

- (void)keyDown:(NSEvent*)event
{
    _inputState.setModifiers(rendererModifierMaskFromEvent(event));
    NSString* key = event.charactersIgnoringModifiers.lowercaseString;
    if ((event.modifierFlags & NSEventModifierFlagCommand) != 0 && [key isEqualToString:@"o"]) {
        [self openMeshDocument];
        return;
    }
    if ([key isEqualToString:@"1"]) {
        [self.meshDelegate setViewMode:mesh2splat::renderer::RenderViewMode::Combined];
        [self refreshRendererStatus];
        return;
    }
    if ([key isEqualToString:@"2"]) {
        [self.meshDelegate setViewMode:mesh2splat::renderer::RenderViewMode::MeshOnly];
        [self refreshRendererStatus];
        return;
    }
    if ([key isEqualToString:@"3"]) {
        [self.meshDelegate setViewMode:mesh2splat::renderer::RenderViewMode::GaussianOnly];
        [self refreshRendererStatus];
        return;
    }
    if ([key isEqualToString:@"]"]) {
        [self increaseGaussianScale:self];
        return;
    }
    if ([key isEqualToString:@"["]) {
        [self decreaseGaussianScale:self];
        return;
    }
    if ([key isEqualToString:@"0"]) {
        [self resetGaussianScale:self];
        return;
    }
    if ([key isEqualToString:@"4"]) {
        [self setLowConversionQuality:self];
        return;
    }
    if ([key isEqualToString:@"5"]) {
        [self setMediumConversionQuality:self];
        return;
    }
    if ([key isEqualToString:@"6"]) {
        [self setHighConversionQuality:self];
        return;
    }

    _inputState.setKey(event.keyCode, true);
    mesh2splat::renderer::RendererInputEvent inputEvent;
    inputEvent.type = mesh2splat::renderer::RendererInputEventType::Key;
    inputEvent.action = mesh2splat::renderer::RendererInputAction::Press;
    inputEvent.code = event.keyCode;
    inputEvent.modifiers = rendererModifierMaskFromEvent(event);
    [self dispatchInputEvent:inputEvent];
}

- (void)keyUp:(NSEvent*)event
{
    _inputState.setModifiers(rendererModifierMaskFromEvent(event));
    _inputState.setKey(event.keyCode, false);
    mesh2splat::renderer::RendererInputEvent inputEvent;
    inputEvent.type = mesh2splat::renderer::RendererInputEventType::Key;
    inputEvent.action = mesh2splat::renderer::RendererInputAction::Release;
    inputEvent.code = event.keyCode;
    inputEvent.modifiers = rendererModifierMaskFromEvent(event);
    [self dispatchInputEvent:inputEvent];
}

- (void)flagsChanged:(NSEvent*)event
{
    _inputState.setModifiers(rendererModifierMaskFromEvent(event));
    mesh2splat::renderer::RendererInputEvent inputEvent;
    inputEvent.type = mesh2splat::renderer::RendererInputEventType::Modifiers;
    inputEvent.action = mesh2splat::renderer::RendererInputAction::Change;
    inputEvent.code = event.keyCode;
    inputEvent.modifiers = rendererModifierMaskFromEvent(event);
    [self dispatchInputEvent:inputEvent];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    return firstFileURLFromDraggingInfo(sender) == nil ? NSDragOperationNone : NSDragOperationCopy;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender
{
    return [self draggingEntered:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    NSURL* url = firstFileURLFromDraggingInfo(sender);
    if (![self openMeshAtURL:url]) {
        NSBeep();
        return NO;
    }
    return YES;
}

- (mesh2splat::macos::MacBridgeRendererStatusSummary)bridgeStatusSummary
{
    NSRect backingBounds = [self convertRectToBacking:self.bounds];
    NSString* diagnostic = self.lastDiagnosticMessage.length > 0 ? self.lastDiagnosticMessage : nil;
    mesh2splat::macos::MacBridgeRendererStatusSummary summary =
        [self.meshDelegate rendererStatusSummaryWithDrawableWidth:static_cast<uint32_t>(std::max<CGFloat>(1.0, std::round(NSWidth(backingBounds))))
                                                   drawableHeight:static_cast<uint32_t>(std::max<CGFloat>(1.0, std::round(NSHeight(backingBounds))))
                                                     backingScale:backingScaleForView(self)
                                                diagnosticOverride:diagnostic];
    summary.canStartConversion = summary.canStartConversion && _bridgeConversionEnabled;
    return summary;
}

- (mesh2splat::macos::MacBridgeActionResult)performBridgeCommand:(const mesh2splat::macos::MacBridgeUiCommand&)command
{
    mesh2splat::macos::MacBridgeActionResult result;
    result.accepted = true;

    switch (command.kind) {
    case mesh2splat::macos::MacBridgeUiCommandKind::None:
        result.completed = true;
        break;
    case mesh2splat::macos::MacBridgeUiCommandKind::OpenDocument:
        [self openMeshDocument];
        result.completed = true;
        result.message = "Open document panel requested.";
        break;
    case mesh2splat::macos::MacBridgeUiCommandKind::OpenScenePath:
        result.completed = [self openMeshAtURL:[NSURL fileURLWithPath:stringFromUtf8(command.filePath)]] ? true : false;
        result.message = result.completed ? "Scene opened." : std::string("Scene open failed.");
        break;
    case mesh2splat::macos::MacBridgeUiCommandKind::SetViewMode:
        [self.meshDelegate setViewMode:rendererViewModeFromMac(command.viewMode)];
        [self refreshRendererStatus];
        result.completed = true;
        result.message = "View mode updated.";
        break;
    case mesh2splat::macos::MacBridgeUiCommandKind::IncreaseGaussianScale:
        [self.meshDelegate setGaussianScale:[self.meshDelegate gaussianScale] * 1.2f];
        [self refreshRendererStatus];
        result.completed = true;
        result.message = "Gaussian scale increased.";
        break;
    case mesh2splat::macos::MacBridgeUiCommandKind::DecreaseGaussianScale:
        [self.meshDelegate setGaussianScale:[self.meshDelegate gaussianScale] / 1.2f];
        [self refreshRendererStatus];
        result.completed = true;
        result.message = "Gaussian scale decreased.";
        break;
    case mesh2splat::macos::MacBridgeUiCommandKind::ResetGaussianScale:
        [self.meshDelegate setGaussianScale:1.0f];
        [self refreshRendererStatus];
        result.completed = true;
        result.message = "Gaussian scale reset.";
        break;
    case mesh2splat::macos::MacBridgeUiCommandKind::SetGaussianScale:
        [self.meshDelegate setGaussianScale:command.gaussianScale];
        [self refreshRendererStatus];
        result.completed = true;
        result.message = "Gaussian scale updated.";
        break;
    case mesh2splat::macos::MacBridgeUiCommandKind::SetConversionSamplesPerTriangle:
        result = [self.meshDelegate startConversionWithSamplesPerTriangle:command.conversionSamplesPerTriangle];
        break;
    case mesh2splat::macos::MacBridgeUiCommandKind::ApplyRenderSettings:
        [self applyRenderMode:static_cast<NSInteger>(command.renderMode)
                    splatSize:command.gaussianScale
                     exposure:command.exposure
                        gamma:command.gamma
         backgroundBrightness:command.backgroundBrightness
conversionSamplesPerTriangle:static_cast<NSInteger>(command.conversionSamplesPerTriangle)
               sortingEnabled:command.gaussianSortingEnabled
         meshRenderingEnabled:command.meshRenderingEnabled
     gaussianRenderingEnabled:command.gaussianRenderingEnabled
            conversionEnabled:command.meshToGaussianConversionEnabled
            depthTestEnabled:command.depthTestEnabled
         splitScreenEnabled:command.splitScreenEnabled
        splitScreenPosition:command.splitScreenPosition
             lightingEnabled:command.lightingEnabled
              shadowsEnabled:command.shadowsEnabled
              lightPositionX:command.lightPositionX
              lightPositionY:command.lightPositionY
              lightPositionZ:command.lightPositionZ
              lightIntensity:command.lightIntensity
               lightColorRed:command.lightColorRed
             lightColorGreen:command.lightColorGreen
              lightColorBlue:command.lightColorBlue
                  debugFlags:command.debugFlags];
        result.completed = true;
        result.message = "Render settings updated.";
        break;
    case mesh2splat::macos::MacBridgeUiCommandKind::RefreshRendererStatus:
        [self refreshRendererStatus];
        result.completed = true;
        result.message = "Renderer status refreshed.";
        break;
    }

    result.status = [self bridgeStatusSummary];
    return result;
}

@end
