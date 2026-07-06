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

BOOL Mesh2SplatExportGaussianPlyFromView(NSView* view, NSURL* url)
{
    if (![view isKindOfClass:Mesh2SplatMetalView.class]) {
        return NO;
    }

    SEL selector = NSSelectorFromString(@"exportGaussianPlyAtURL:");
    if (![view respondsToSelector:selector]) {
        return NO;
    }

    using ExportPlyMessage = BOOL (*)(id, SEL, NSURL*);
    ExportPlyMessage message = reinterpret_cast<ExportPlyMessage>(objc_msgSend);
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
    if (![view isKindOfClass:Mesh2SplatMetalView.class]) {
        return;
    }

    [view.window makeFirstResponder:view];
}

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
                                          uint32_t debugFlags)
{
    if (![view isKindOfClass:Mesh2SplatMetalView.class]) {
        return;
    }

    SEL selector = NSSelectorFromString(@"applyRenderMode:splatSize:exposure:gamma:backgroundBrightness:conversionSamplesPerTriangle:sortingEnabled:meshRenderingEnabled:gaussianRenderingEnabled:conversionEnabled:depthTestEnabled:splitScreenEnabled:splitScreenPosition:lightingEnabled:lightPositionX:lightPositionY:lightPositionZ:lightIntensity:lightColorRed:lightColorGreen:lightColorBlue:debugFlags:");
    if (![view respondsToSelector:selector]) {
        return;
    }

    using ApplySettingsMessage = void (*)(
        id,
        SEL,
        NSInteger,
        double,
        double,
        double,
        double,
        NSInteger,
        BOOL,
        BOOL,
        BOOL,
        BOOL,
        BOOL,
        BOOL,
        double,
        BOOL,
        double,
        double,
        double,
        double,
        double,
        double,
        double,
        uint32_t);
    ApplySettingsMessage message = reinterpret_cast<ApplySettingsMessage>(objc_msgSend);
    message(view,
            selector,
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
            lightPositionX,
            lightPositionY,
            lightPositionZ,
            lightIntensity,
            lightColorRed,
            lightColorGreen,
            lightColorBlue,
            debugFlags);
}
