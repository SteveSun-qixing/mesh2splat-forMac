#include "MetalView.hpp"

#include "renderer/metal/MetalRenderer.hpp"

#import <Foundation/Foundation.h>

#include <memory>

@interface Mesh2SplatMetalViewDelegate : NSObject <MTKViewDelegate>

- (instancetype)initWithView:(MTKView*)view;

@end

@implementation Mesh2SplatMetalViewDelegate {
    std::unique_ptr<mesh2splat::metal::MetalRenderer> _renderer;
}

- (instancetype)initWithView:(MTKView*)view
{
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _renderer = std::make_unique<mesh2splat::metal::MetalRenderer>((__bridge void*)view.device);
    if (!_renderer->initialize()) {
        NSLog(@"Failed to initialize Metal renderer.");
        return nil;
    }

    CGSize drawableSize = view.drawableSize;
    _renderer->resize(static_cast<uint32_t>(drawableSize.width), static_cast<uint32_t>(drawableSize.height));
    return self;
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size
{
    if (_renderer != nullptr) {
        _renderer->resize(static_cast<uint32_t>(size.width), static_cast<uint32_t>(size.height));
    }
}

- (void)drawInMTKView:(MTKView*)view
{
    id<CAMetalDrawable> drawable = view.currentDrawable;
    MTLRenderPassDescriptor* descriptor = view.currentRenderPassDescriptor;
    if (drawable == nil || descriptor == nil || _renderer == nullptr) {
        return;
    }

    _renderer->draw((__bridge void*)descriptor, (__bridge void*)drawable);
}

@end

@interface Mesh2SplatMetalView ()

@property (nonatomic, strong) Mesh2SplatMetalViewDelegate* meshDelegate;

@end

@implementation Mesh2SplatMetalView

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
    self.preferredFramesPerSecond = 60;
    self.enableSetNeedsDisplay = NO;
    self.paused = NO;
    self.framebufferOnly = YES;

    self.meshDelegate = [[Mesh2SplatMetalViewDelegate alloc] initWithView:self];
    self.delegate = self.meshDelegate;
    return self;
}

@end
