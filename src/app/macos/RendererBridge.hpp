#pragma once

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, M2SRendererRuntimeState) {
    M2SRendererRuntimeStateUnknown = 0,
    M2SRendererRuntimeStateReady = 1,
    M2SRendererRuntimeStateLoading = 2,
    M2SRendererRuntimeStateConverting = 3,
    M2SRendererRuntimeStateRendering = 4,
    M2SRendererRuntimeStateFailed = 5,
    M2SRendererRuntimeStateExporting = 6,
};

typedef NS_ENUM(NSUInteger, M2SRendererDiagnosticSeverity) {
    M2SRendererDiagnosticSeverityInfo = 0,
    M2SRendererDiagnosticSeverityWarning = 1,
    M2SRendererDiagnosticSeverityError = 2,
};

@interface M2SRendererFrameStats : NSObject

@property (nonatomic, assign) uint64_t submittedFrameCount;
@property (nonatomic, assign) uint64_t completedFrameCount;
@property (nonatomic, assign) uint64_t failedFrameCount;
@property (nonatomic, assign) double lastCpuEncodeMs;
@property (nonatomic, assign) double averageCpuEncodeMs;
@property (nonatomic, assign) double lastGpuMs;
@property (nonatomic, assign) double averageGpuMs;
@property (nonatomic, assign) BOOL lastRenderedMesh;
@property (nonatomic, assign) BOOL lastRenderedGaussians;
@property (nonatomic, assign) BOOL lastSortedGaussians;

@end

@interface M2SRendererBackendStatus : NSObject

@property (nonatomic, assign) M2SRendererRuntimeState runtimeState;
@property (nonatomic, copy) NSString* backendName;
@property (nonatomic, copy) NSString* deviceName;
@property (nonatomic, assign) BOOL supported;
@property (nonatomic, assign) BOOL initialized;
@property (nonatomic, assign) BOOL shaderLibraryReady;
@property (nonatomic, assign) BOOL pipelineCacheReady;

@end

@interface M2SRendererResourceStats : NSObject

@property (nonatomic, assign) uint64_t frameUniformBytes;
@property (nonatomic, assign) uint64_t sceneBytes;
@property (nonatomic, assign) uint64_t gaussianBytes;
@property (nonatomic, assign) uint64_t gaussianSortBytes;
@property (nonatomic, assign) uint64_t shadowBytes;
@property (nonatomic, assign) uint64_t pendingConversionBytes;
@property (nonatomic, assign) uint64_t trackedBytes;
@property (nonatomic, assign) uint32_t meshCount;
@property (nonatomic, assign) uint32_t materialCount;
@property (nonatomic, assign) uint32_t textureCount;
@property (nonatomic, assign) uint32_t gaussianCount;

@end

@interface M2SRendererConversionStats : NSObject

@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) float progress;
@property (nonatomic, assign) uint32_t samplesPerTriangle;
@property (nonatomic, assign) uint32_t convertedGaussianCount;
@property (nonatomic, assign) uint64_t submittedConversionCount;
@property (nonatomic, assign) uint64_t completedConversionCount;
@property (nonatomic, assign) uint64_t failedConversionCount;
@property (nonatomic, assign) double lastCpuSubmitMs;
@property (nonatomic, assign) double averageCpuSubmitMs;
@property (nonatomic, assign) double lastGpuMs;
@property (nonatomic, assign) double averageGpuMs;

@end

@interface M2SRendererStatus : NSObject

@property (nonatomic, assign) M2SRendererRuntimeState runtimeState;
@property (nonatomic, assign) M2SRendererDiagnosticSeverity diagnosticSeverity;
@property (nonatomic, copy) NSString* statusText;
@property (nonatomic, copy) NSString* loadedScenePath;
@property (nonatomic, copy) NSString* loadedSceneName;
@property (nonatomic, copy) NSString* exportedFilePath;
@property (nonatomic, copy) NSString* errorMessage;
@property (nonatomic, assign) uint32_t drawableWidth;
@property (nonatomic, assign) uint32_t drawableHeight;
@property (nonatomic, assign) float backingScale;
@property (nonatomic, assign) uint32_t convertedGaussianCount;
@property (nonatomic, assign) uint32_t conversionSamplesPerTriangle;
@property (nonatomic, assign) float conversionProgress;
@property (nonatomic, assign) float gaussianScale;
@property (nonatomic, assign) float exposure;
@property (nonatomic, assign) float gamma;
@property (nonatomic, assign) float backgroundBrightness;
@property (nonatomic, assign) BOOL lightingEnabled;
@property (nonatomic, assign) float lightPositionX;
@property (nonatomic, assign) float lightPositionY;
@property (nonatomic, assign) float lightPositionZ;
@property (nonatomic, assign) float lightIntensity;
@property (nonatomic, assign) float lightColorRed;
@property (nonatomic, assign) float lightColorGreen;
@property (nonatomic, assign) float lightColorBlue;
@property (nonatomic, assign) uint32_t debugFlags;
@property (nonatomic, assign) NSUInteger viewMode;
@property (nonatomic, assign) NSUInteger gaussianVisualizationMode;
@property (nonatomic, assign, getter=isConverting) BOOL converting;
@property (nonatomic, assign) BOOL hasScene;
@property (nonatomic, assign) BOOL hasGaussians;
@property (nonatomic, assign) BOOL hasVisibleMesh;
@property (nonatomic, assign) BOOL canImportScene;
@property (nonatomic, assign) BOOL canStartConversion;
@property (nonatomic, assign) BOOL canExportGaussians;
@property (nonatomic, assign) BOOL exportMatchesCurrentConversion;
@property (nonatomic, assign) BOOL meshRenderingEnabled;
@property (nonatomic, assign) BOOL gaussianRenderingEnabled;
@property (nonatomic, assign) BOOL gaussianSortingEnabled;
@property (nonatomic, assign) BOOL meshToGaussianConversionEnabled;
@property (nonatomic, assign) BOOL depthTestEnabled;
@property (nonatomic, assign) BOOL splitScreenEnabled;
@property (nonatomic, assign) float splitScreenPosition;
@property (nonatomic, assign) BOOL shadowsEnabled;
@property (nonatomic, strong) M2SRendererFrameStats* frameStats;
@property (nonatomic, strong) M2SRendererBackendStatus* backendStatus;
@property (nonatomic, strong) M2SRendererResourceStats* resourceStats;
@property (nonatomic, strong) M2SRendererConversionStats* conversionStats;

@end

@interface M2SRendererActionResult : NSObject

@property (nonatomic, assign, getter=isAccepted) BOOL accepted;
@property (nonatomic, assign, getter=isCompleted) BOOL completed;
@property (nonatomic, copy) NSString* message;
@property (nonatomic, strong) M2SRendererStatus* status;

@end

@interface M2SRendererBridge : NSObject

- (instancetype)initWithMetalView:(NSView*)metalView NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (M2SRendererStatus*)rendererStatus;
- (M2SRendererActionResult*)importMeshAtURL:(NSURL*)url;
- (M2SRendererActionResult*)startConversionWithSamplesPerTriangle:(uint32_t)samplesPerTriangle;
- (M2SRendererActionResult*)refreshRendererStatus;

@end

NS_ASSUME_NONNULL_END
