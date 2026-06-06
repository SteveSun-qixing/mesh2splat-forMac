#pragma once

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

NSView* Mesh2SplatCreateMetalView(NSRect frame);
BOOL Mesh2SplatOpenMeshInView(NSView* view, NSURL* url);
void Mesh2SplatRefreshMetalViewStatus(NSView* view);
void Mesh2SplatFocusMetalView(NSView* view);
void Mesh2SplatApplyRenderSettingsToView(NSView* view,
                                          NSInteger renderMode,
                                          double splatSize,
                                          double exposure,
                                          double gamma,
                                          double backgroundBrightness,
                                          NSInteger conversionSamplesPerTriangle,
                                          BOOL sortingEnabled,
                                          BOOL meshRenderingEnabled,
                                          BOOL gaussianRenderingEnabled,
                                          BOOL conversionEnabled);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
