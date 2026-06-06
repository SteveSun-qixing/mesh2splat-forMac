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

@interface M2SRendererStatus : NSObject

@property (nonatomic, assign) M2SRendererRuntimeState runtimeState;
@property (nonatomic, assign) M2SRendererDiagnosticSeverity diagnosticSeverity;
@property (nonatomic, copy) NSString* statusText;
@property (nonatomic, copy) NSString* loadedScenePath;
@property (nonatomic, copy) NSString* errorMessage;
@property (nonatomic, assign) uint32_t drawableWidth;
@property (nonatomic, assign) uint32_t drawableHeight;
@property (nonatomic, assign) float backingScale;
@property (nonatomic, assign) uint32_t convertedGaussianCount;
@property (nonatomic, assign) uint32_t conversionSamplesPerTriangle;
@property (nonatomic, assign) float conversionProgress;
@property (nonatomic, assign) float gaussianScale;
@property (nonatomic, assign, getter=isConverting) BOOL converting;
@property (nonatomic, assign) BOOL hasScene;
@property (nonatomic, assign) BOOL hasGaussians;
@property (nonatomic, strong) M2SRendererFrameStats* frameStats;

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
