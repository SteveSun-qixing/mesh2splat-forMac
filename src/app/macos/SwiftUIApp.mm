#include "SwiftUIApp.hpp"

#include "MetalView.hpp"

#include <objc/message.h>

NSView* Mesh2SplatCreateMetalView(NSRect frame)
{
    Mesh2SplatMetalView* view = [[Mesh2SplatMetalView alloc] initWithFrame:frame];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    return view;
}

BOOL Mesh2SplatOpenMeshInView(NSView* view, NSURL* url)
{
    if (![view isKindOfClass:Mesh2SplatMetalView.class]) {
        return NO;
    }

    SEL selector = NSSelectorFromString(@"openMeshAtURL:");
    if (![view respondsToSelector:selector]) {
        return NO;
    }

    using OpenMeshMessage = BOOL (*)(id, SEL, NSURL*);
    OpenMeshMessage message = reinterpret_cast<OpenMeshMessage>(objc_msgSend);
    return message(view, selector, url);
}

void Mesh2SplatRefreshMetalViewStatus(NSView* view)
{
    if (![view isKindOfClass:Mesh2SplatMetalView.class]) {
        return;
    }

    SEL selector = NSSelectorFromString(@"refreshRendererStatus");
    if ([view respondsToSelector:selector]) {
        using RefreshMessage = void (*)(id, SEL);
        RefreshMessage message = reinterpret_cast<RefreshMessage>(objc_msgSend);
        message(view, selector);
    }
}

void Mesh2SplatFocusMetalView(NSView* view)
{
    if ([view isKindOfClass:Mesh2SplatMetalView.class]) {
        [view.window makeFirstResponder:view];
    }
}
