#pragma once

#include "MacBridgeTypes.hpp"

#import <MetalKit/MetalKit.h>

#include <stdint.h>

@interface Mesh2SplatMetalView : MTKView

- (instancetype)initWithFrame:(NSRect)frameRect;
- (IBAction)openDocument:(id)sender;
- (IBAction)exportDocument:(id)sender;
- (BOOL)openMeshAtURL:(NSURL*)url;
- (BOOL)exportGaussianPlyAtURL:(NSURL*)url;
- (void)refreshRendererStatus;
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
             debugFlags:(uint32_t)debugFlags;
- (mesh2splat::macos::MacBridgeRendererStatusSummary)bridgeStatusSummary;
- (mesh2splat::macos::MacBridgeActionResult)performBridgeCommand:(const mesh2splat::macos::MacBridgeUiCommand&)command;

@end
