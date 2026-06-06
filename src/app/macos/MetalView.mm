#include "MetalView.hpp"

#include "core/InputState.hpp"
#include "renderer/RendererInterface.hpp"

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <memory>
#include <string>

@class Mesh2SplatMetalViewDelegate;

@interface Mesh2SplatMetalView ()

@property (nonatomic, strong) Mesh2SplatMetalViewDelegate* meshDelegate;

- (const mesh2splat::core::InputState&)inputState;
- (void)beginInputFrame;
- (void)openMeshDocument;
- (void)updateWindowTitle;

@end

@interface Mesh2SplatMetalViewDelegate : NSObject <MTKViewDelegate>

- (instancetype)initWithView:(Mesh2SplatMetalView*)view;
- (BOOL)loadMeshAtPath:(NSString*)path;
- (void)setViewMode:(mesh2splat::renderer::RenderViewMode)mode;
- (void)setGaussianScale:(float)scale;
- (float)gaussianScale;
- (BOOL)setConversionSamplesPerTriangle:(uint32_t)samplesPerTriangle;
- (NSString*)rendererStatusTitle;

@end

@implementation Mesh2SplatMetalViewDelegate {
    std::unique_ptr<mesh2splat::renderer::Renderer> _renderer;
    __weak Mesh2SplatMetalView* _view;
    CFTimeInterval _lastFrameTime;
}

- (instancetype)initWithView:(Mesh2SplatMetalView*)view
{
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _view = view;
    _lastFrameTime = CACurrentMediaTime();
    _renderer = mesh2splat::renderer::createMetalRenderer((__bridge void*)view.device);
    if (!_renderer->initialize()) {
        const std::string& diagnostic = _renderer->lastDiagnostic();
        if (diagnostic.empty()) {
            NSLog(@"Failed to initialize Metal renderer.");
        } else {
            NSLog(@"Failed to initialize Metal renderer: %s", diagnostic.c_str());
        }
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

    Mesh2SplatMetalView* owner = _view;
    if (owner == nil) {
        return;
    }

    const CFTimeInterval now = CACurrentMediaTime();
    const double deltaTime = static_cast<double>(now - _lastFrameTime);
    _lastFrameTime = now;
    _renderer->draw((__bridge void*)descriptor, (__bridge void*)drawable, [owner inputState], deltaTime);
    [owner beginInputFrame];
}

- (BOOL)loadMeshAtPath:(NSString*)path
{
    if (_renderer == nullptr || path == nil) {
        return NO;
    }

    return _renderer->loadMeshFile(std::string(path.UTF8String)) ? YES : NO;
}

- (void)setViewMode:(mesh2splat::renderer::RenderViewMode)mode
{
    if (_renderer != nullptr) {
        _renderer->setViewMode(mode);
    }
}

- (void)setGaussianScale:(float)scale
{
    if (_renderer != nullptr) {
        _renderer->setGaussianScale(scale);
    }
}

- (float)gaussianScale
{
    return _renderer == nullptr ? 1.0f : _renderer->gaussianScale();
}

- (BOOL)setConversionSamplesPerTriangle:(uint32_t)samplesPerTriangle
{
    return _renderer != nullptr && _renderer->setConversionSamplesPerTriangle(samplesPerTriangle) ? YES : NO;
}

- (NSString*)rendererStatusTitle
{
    if (_renderer == nullptr) {
        return @"Mesh2Splat Metal";
    }

    NSString* mode = @"Combined";
    switch (_renderer->viewMode()) {
    case mesh2splat::renderer::RenderViewMode::Combined:
        mode = @"Combined";
        break;
    case mesh2splat::renderer::RenderViewMode::MeshOnly:
        mode = @"Mesh";
        break;
    case mesh2splat::renderer::RenderViewMode::GaussianOnly:
        mode = @"Gaussians";
        break;
    }

    NSString* assetName = @"Preview";
    const std::string& loadedPath = _renderer->loadedMeshPath();
    if (!loadedPath.empty()) {
        assetName = [[NSString stringWithUTF8String:loadedPath.c_str()] lastPathComponent];
    }

    return [NSString stringWithFormat:@"Mesh2Splat Metal - %@ - %@ - %u gaussians - scale x%.2f - quality %ux",
                                      assetName,
                                      mode,
                                      _renderer->convertedGaussianCount(),
                                      _renderer->gaussianScale(),
                                      _renderer->conversionSamplesPerTriangle()];
}

@end

@implementation Mesh2SplatMetalView {
    mesh2splat::core::InputState _inputState;
}

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

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self.window makeFirstResponder:self];
    [self updateWindowTitle];
}

- (void)beginInputFrame
{
    _inputState.beginFrame();
}

- (const mesh2splat::core::InputState&)inputState
{
    return _inputState;
}

- (void)openMeshDocument
{
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    NSMutableArray<UTType*>* contentTypes = [NSMutableArray array];
    UTType* glbType = [UTType typeWithFilenameExtension:@"glb"];
    UTType* gltfType = [UTType typeWithFilenameExtension:@"gltf"];
    if (glbType != nil) {
        [contentTypes addObject:glbType];
    }
    if (gltfType != nil) {
        [contentTypes addObject:gltfType];
    }
    panel.allowedContentTypes = contentTypes;

    __weak Mesh2SplatMetalView* weakSelf = self;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        Mesh2SplatMetalView* strongSelf = weakSelf;
        if (strongSelf == nil || response != NSModalResponseOK) {
            return;
        }

        NSURL* url = panel.URL;
        if (url == nil || ![strongSelf.meshDelegate loadMeshAtPath:url.path]) {
            NSBeep();
            return;
        }

        [strongSelf updateWindowTitle];
    }];
}

- (void)updateWindowTitle
{
    if (self.window != nil) {
        self.window.title = [self.meshDelegate rendererStatusTitle];
    }
}

- (IBAction)openDocument:(id)sender
{
    (void)sender;
    [self openMeshDocument];
}

- (IBAction)showCombinedView:(id)sender
{
    (void)sender;
    [self.meshDelegate setViewMode:mesh2splat::renderer::RenderViewMode::Combined];
    [self updateWindowTitle];
}

- (IBAction)showMeshView:(id)sender
{
    (void)sender;
    [self.meshDelegate setViewMode:mesh2splat::renderer::RenderViewMode::MeshOnly];
    [self updateWindowTitle];
}

- (IBAction)showGaussianView:(id)sender
{
    (void)sender;
    [self.meshDelegate setViewMode:mesh2splat::renderer::RenderViewMode::GaussianOnly];
    [self updateWindowTitle];
}

- (IBAction)increaseGaussianScale:(id)sender
{
    (void)sender;
    [self.meshDelegate setGaussianScale:[self.meshDelegate gaussianScale] * 1.2f];
    [self updateWindowTitle];
}

- (IBAction)decreaseGaussianScale:(id)sender
{
    (void)sender;
    [self.meshDelegate setGaussianScale:[self.meshDelegate gaussianScale] / 1.2f];
    [self updateWindowTitle];
}

- (IBAction)resetGaussianScale:(id)sender
{
    (void)sender;
    [self.meshDelegate setGaussianScale:1.0f];
    [self updateWindowTitle];
}

- (IBAction)setLowConversionQuality:(id)sender
{
    (void)sender;
    if (![self.meshDelegate setConversionSamplesPerTriangle:1]) {
        NSBeep();
    }
    [self updateWindowTitle];
}

- (IBAction)setMediumConversionQuality:(id)sender
{
    (void)sender;
    if (![self.meshDelegate setConversionSamplesPerTriangle:4]) {
        NSBeep();
    }
    [self updateWindowTitle];
}

- (IBAction)setHighConversionQuality:(id)sender
{
    (void)sender;
    if (![self.meshDelegate setConversionSamplesPerTriangle:9]) {
        NSBeep();
    }
    [self updateWindowTitle];
}

- (void)updateMousePosition:(NSEvent*)event
{
    NSPoint location = [self convertPoint:event.locationInWindow fromView:nil];
    _inputState.updateMousePosition(location.x, location.y);
}

- (void)mouseMoved:(NSEvent*)event
{
    [self updateMousePosition:event];
}

- (void)mouseDragged:(NSEvent*)event
{
    [self updateMousePosition:event];
}

- (void)rightMouseDragged:(NSEvent*)event
{
    [self updateMousePosition:event];
}

- (void)otherMouseDragged:(NSEvent*)event
{
    [self updateMousePosition:event];
}

- (void)mouseDown:(NSEvent*)event
{
    [self updateMousePosition:event];
    _inputState.setMouseButton(0, true);
}

- (void)mouseUp:(NSEvent*)event
{
    [self updateMousePosition:event];
    _inputState.setMouseButton(0, false);
}

- (void)rightMouseDown:(NSEvent*)event
{
    [self updateMousePosition:event];
    _inputState.setMouseButton(1, true);
}

- (void)rightMouseUp:(NSEvent*)event
{
    [self updateMousePosition:event];
    _inputState.setMouseButton(1, false);
}

- (void)otherMouseDown:(NSEvent*)event
{
    [self updateMousePosition:event];
    _inputState.setMouseButton(2, true);
}

- (void)otherMouseUp:(NSEvent*)event
{
    [self updateMousePosition:event];
    _inputState.setMouseButton(2, false);
}

- (void)scrollWheel:(NSEvent*)event
{
    _inputState.addScrollDelta(event.scrollingDeltaX, event.scrollingDeltaY);
}

- (void)keyDown:(NSEvent*)event
{
    NSString* key = event.charactersIgnoringModifiers.lowercaseString;
    if ((event.modifierFlags & NSEventModifierFlagCommand) != 0 && [key isEqualToString:@"o"]) {
        [self openMeshDocument];
        return;
    }
    if ([key isEqualToString:@"1"]) {
        [self.meshDelegate setViewMode:mesh2splat::renderer::RenderViewMode::Combined];
        [self updateWindowTitle];
        return;
    }
    if ([key isEqualToString:@"2"]) {
        [self.meshDelegate setViewMode:mesh2splat::renderer::RenderViewMode::MeshOnly];
        [self updateWindowTitle];
        return;
    }
    if ([key isEqualToString:@"3"]) {
        [self.meshDelegate setViewMode:mesh2splat::renderer::RenderViewMode::GaussianOnly];
        [self updateWindowTitle];
        return;
    }
    if ([key isEqualToString:@"]"]) {
        [self increaseGaussianScale:self];
        return;
    }
    if ([key isEqualToString:@"["]) {
        [self decreaseGaussianScale:self];
        return;
    }
    if ([key isEqualToString:@"0"]) {
        [self resetGaussianScale:self];
        return;
    }
    if ([key isEqualToString:@"4"]) {
        [self setLowConversionQuality:self];
        return;
    }
    if ([key isEqualToString:@"5"]) {
        [self setMediumConversionQuality:self];
        return;
    }
    if ([key isEqualToString:@"6"]) {
        [self setHighConversionQuality:self];
        return;
    }

    _inputState.setKey(event.keyCode, true);
}

- (void)keyUp:(NSEvent*)event
{
    _inputState.setKey(event.keyCode, false);
}

@end
