#pragma once

#include "MacBridgeTypes.hpp"

#import <MetalKit/MetalKit.h>

@interface Mesh2SplatMetalView : MTKView

- (instancetype)initWithFrame:(NSRect)frameRect;
- (IBAction)openDocument:(id)sender;
- (IBAction)exportDocument:(id)sender;
- (BOOL)openMeshAtURL:(NSURL*)url;
- (void)refreshRendererStatus;
- (mesh2splat::macos::MacBridgeRendererStatusSummary)bridgeStatusSummary;
- (mesh2splat::macos::MacBridgeActionResult)performBridgeCommand:(const mesh2splat::macos::MacBridgeUiCommand&)command;

@end
