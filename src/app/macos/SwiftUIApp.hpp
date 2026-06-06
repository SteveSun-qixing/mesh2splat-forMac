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

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
