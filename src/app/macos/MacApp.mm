#include "MetalView.hpp"

#import <AppKit/AppKit.h>

@interface Mesh2SplatAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>

@property (nonatomic, strong) NSWindow* window;

@end

@implementation Mesh2SplatAppDelegate

- (void)configureMainMenu
{
    NSMenu* mainMenu = [[NSMenu alloc] initWithTitle:@"Main Menu"];

    NSMenuItem* appMenuItem = [[NSMenuItem alloc] initWithTitle:@""
                                                         action:nil
                                                  keyEquivalent:@""];
    [mainMenu addItem:appMenuItem];

    NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@"Mesh2Splat Metal"];
    NSMenuItem* quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Mesh2Splat Metal"
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    quitItem.target = NSApp;
    [appMenu addItem:quitItem];
    appMenuItem.submenu = appMenu;

    NSMenuItem* fileMenuItem = [[NSMenuItem alloc] initWithTitle:@"File"
                                                          action:nil
                                                   keyEquivalent:@""];
    [mainMenu addItem:fileMenuItem];

    NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    NSMenuItem* openItem = [[NSMenuItem alloc] initWithTitle:@"Open..."
                                                      action:@selector(openDocument:)
                                               keyEquivalent:@"o"];
    openItem.target = nil;
    [fileMenu addItem:openItem];
    fileMenuItem.submenu = fileMenu;

    NSMenuItem* viewMenuItem = [[NSMenuItem alloc] initWithTitle:@"View"
                                                          action:nil
                                                   keyEquivalent:@""];
    [mainMenu addItem:viewMenuItem];

    NSMenu* viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem* combinedItem = [[NSMenuItem alloc] initWithTitle:@"Combined"
                                                          action:@selector(showCombinedView:)
                                                   keyEquivalent:@"1"];
    combinedItem.target = nil;
    [viewMenu addItem:combinedItem];

    NSMenuItem* meshItem = [[NSMenuItem alloc] initWithTitle:@"Mesh"
                                                      action:@selector(showMeshView:)
                                               keyEquivalent:@"2"];
    meshItem.target = nil;
    [viewMenu addItem:meshItem];

    NSMenuItem* gaussianItem = [[NSMenuItem alloc] initWithTitle:@"Gaussians"
                                                          action:@selector(showGaussianView:)
                                                   keyEquivalent:@"3"];
    gaussianItem.target = nil;
    [viewMenu addItem:gaussianItem];
    [viewMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* smallerItem = [[NSMenuItem alloc] initWithTitle:@"Smaller Gaussians"
                                                         action:@selector(decreaseGaussianScale:)
                                                  keyEquivalent:@"["];
    smallerItem.target = nil;
    [viewMenu addItem:smallerItem];

    NSMenuItem* largerItem = [[NSMenuItem alloc] initWithTitle:@"Larger Gaussians"
                                                        action:@selector(increaseGaussianScale:)
                                                 keyEquivalent:@"]"];
    largerItem.target = nil;
    [viewMenu addItem:largerItem];

    NSMenuItem* resetScaleItem = [[NSMenuItem alloc] initWithTitle:@"Reset Gaussian Size"
                                                            action:@selector(resetGaussianScale:)
                                                     keyEquivalent:@"0"];
    resetScaleItem.target = nil;
    [viewMenu addItem:resetScaleItem];
    [viewMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* lowQualityItem = [[NSMenuItem alloc] initWithTitle:@"Conversion Quality 1x"
                                                            action:@selector(setLowConversionQuality:)
                                                     keyEquivalent:@"4"];
    lowQualityItem.target = nil;
    [viewMenu addItem:lowQualityItem];

    NSMenuItem* mediumQualityItem = [[NSMenuItem alloc] initWithTitle:@"Conversion Quality 4x"
                                                               action:@selector(setMediumConversionQuality:)
                                                        keyEquivalent:@"5"];
    mediumQualityItem.target = nil;
    [viewMenu addItem:mediumQualityItem];

    NSMenuItem* highQualityItem = [[NSMenuItem alloc] initWithTitle:@"Conversion Quality 9x"
                                                             action:@selector(setHighConversionQuality:)
                                                      keyEquivalent:@"6"];
    highQualityItem.target = nil;
    [viewMenu addItem:highQualityItem];
    viewMenuItem.submenu = viewMenu;

    NSApp.mainMenu = mainMenu;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification
{
    (void)notification;

    [self configureMainMenu];

    NSRect frame = NSMakeRect(0, 0, 1280, 800);
    NSUInteger styleMask = NSWindowStyleMaskTitled |
                           NSWindowStyleMaskClosable |
                           NSWindowStyleMaskMiniaturizable |
                           NSWindowStyleMaskResizable;

    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:styleMask
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"Mesh2Splat Metal";
    self.window.delegate = self;
    self.window.contentView = [[Mesh2SplatMetalView alloc] initWithFrame:frame];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender
{
    (void)sender;
    return YES;
}

@end

int main(int argc, char** argv)
{
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication* application = [NSApplication sharedApplication];
        Mesh2SplatAppDelegate* delegate = [[Mesh2SplatAppDelegate alloc] init];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }

    return 0;
}
