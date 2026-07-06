#pragma once

#import "RendererBridge.hpp"

#import <AppKit/AppKit.h>

#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

NSView* Mesh2SplatCreateMetalView(NSRect frame);
BOOL Mesh2SplatOpenMeshInView(NSView* view, NSURL* url);
BOOL Mesh2SplatExportGaussianPlyFromView(NSView* view, NSURL* url);
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
                                          BOOL conversionEnabled,
                                          BOOL depthTestEnabled,
                                          BOOL splitScreenEnabled,
                                          double splitScreenPosition,
                                          BOOL lightingEnabled,
                                          double lightPositionX,
                                          double lightPositionY,
                                          double lightPositionZ,
                                          double lightIntensity,
                                          double lightColorRed,
                                          double lightColorGreen,
                                          double lightColorBlue,
                                          uint32_t debugFlags);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
