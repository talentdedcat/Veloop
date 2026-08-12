#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <InputMethodKit/InputMethodKit.h>
#import <fcntl.h>

static NSString *const VeloopCaretPortName = @"com.veloop.palette.caret-location";
static NSString *const VeloopHostBundleIdentifier = @"com.veloop.app";
static const CFIndex VeloopMaximumMessageBytes = 4096;
static dispatch_source_t VeloopHostWatcher;
static dispatch_queue_t VeloopHostQueue;
static NSUInteger VeloopHostCheckGeneration;

static NSString *VeloopSupportPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Veloop"];
}

static NSString *VeloopHostMarkerPath(void) {
    return [VeloopSupportPath() stringByAppendingPathComponent:@"palette-host-path"];
}

static NSString *VeloopUninstallWatcherPath(void) {
    return [VeloopSupportPath()
        stringByAppendingPathComponent:@"UninstallWatcher/VeloopUninstallWatcher"];
}

static NSString *VeloopRecordedHostPath(void) {
    NSString *path = [NSString stringWithContentsOfFile:VeloopHostMarkerPath()
                                                encoding:NSUTF8StringEncoding
                                                   error:nil];
    return [path stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL VeloopIsUsableHostPath(NSString *path) {
    NSBundle *bundle = path.length > 0 ? [NSBundle bundleWithPath:path] : nil;
    return path.length > 0
        && ![path containsString:@"/.Trash/"]
        && ![path containsString:@"/.Trashes/"]
        && [NSFileManager.defaultManager fileExistsAtPath:path]
        && [VeloopHostBundleIdentifier isEqualToString:bundle.bundleIdentifier];
}

static TISInputSourceRef VeloopInstalledInputSource(void) {
    NSDictionary *filter = @{
        (__bridge NSString *)kTISPropertyInputSourceID: @"com.talentdedcat.veloop.palette",
    };
    CFArrayRef sources = TISCreateInputSourceList((__bridge CFDictionaryRef)filter, true);
    if (sources == nil || CFArrayGetCount(sources) == 0) {
        if (sources != nil) {
            CFRelease(sources);
        }
        return nil;
    }
    TISInputSourceRef source = (TISInputSourceRef)CFRetain(CFArrayGetValueAtIndex(sources, 0));
    CFRelease(sources);
    return source;
}

static void VeloopRemoveInstalledState(void) {
    // The plain watcher owns targeted TCC reset and exact-path cleanup on current installs.
    if ([NSFileManager.defaultManager fileExistsAtPath:VeloopUninstallWatcherPath()]) {
        exit(0);
    }

    TISInputSourceRef source = VeloopInstalledInputSource();
    if (source != nil) {
        TISDeselectInputSource(source);
        TISDisableInputSource(source);
        CFRelease(source);
    }

    NSArray<NSString *> *serviceTargets = @[
        [NSString stringWithFormat:@"gui/%u/com.veloop.service", getuid()],
        [NSString stringWithFormat:@"gui/%u/com.veloop.uninstall-watcher", getuid()],
    ];
    for (NSString *serviceTarget in serviceTargets) {
        NSTask *bootout = [[NSTask alloc] init];
        bootout.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
        bootout.arguments = @[@"bootout", serviceTarget];
        bootout.standardOutput = NSFileHandle.fileHandleWithNullDevice;
        bootout.standardError = NSFileHandle.fileHandleWithNullDevice;
        [bootout launchAndReturnError:nil];
        [bootout waitUntilExit];
    }

    NSString *home = NSHomeDirectory();
    NSArray<NSString *> *paths = @[
        [home stringByAppendingPathComponent:@"Library/Input Methods/VeloopPalette.app"],
        [home stringByAppendingPathComponent:@"Library/LaunchAgents/com.veloop.service.plist"],
        [home stringByAppendingPathComponent:@"Library/LaunchAgents/com.veloop.uninstall-watcher.plist"],
        VeloopHostMarkerPath(),
        [VeloopSupportPath() stringByAppendingPathComponent:@"UninstallWatcher"],
    ];
    for (NSString *path in paths) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    }
    exit(0);
}

static void VeloopStartHostWatcher(void);

static void VeloopCheckHost(void) {
    NSString *recordedPath = VeloopRecordedHostPath();
    if (VeloopIsUsableHostPath(recordedPath)) {
        return;
    }

    NSURL *currentHost = [NSWorkspace.sharedWorkspace
        URLForApplicationWithBundleIdentifier:VeloopHostBundleIdentifier];
    if (VeloopIsUsableHostPath(currentHost.path)) {
        [currentHost.path writeToFile:VeloopHostMarkerPath()
                           atomically:YES
                             encoding:NSUTF8StringEncoding
                                error:nil];
        VeloopStartHostWatcher();
        return;
    }
    VeloopRemoveInstalledState();
}

static void VeloopStartHostWatcher(void) {
    if (VeloopHostWatcher != nil) {
        dispatch_source_cancel(VeloopHostWatcher);
        VeloopHostWatcher = nil;
    }
    NSString *hostPath = VeloopRecordedHostPath();
    NSString *parentPath = hostPath.stringByDeletingLastPathComponent;
    int descriptor = open(parentPath.fileSystemRepresentation, O_EVTONLY);
    if (descriptor < 0) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
            VeloopHostQueue,
            ^{ VeloopCheckHost(); }
        );
        return;
    }

    dispatch_queue_t queue = VeloopHostQueue;
    VeloopHostWatcher = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_VNODE,
        (uintptr_t)descriptor,
        DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_WRITE,
        queue
    );
    dispatch_source_set_cancel_handler(VeloopHostWatcher, ^{ close(descriptor); });
    dispatch_source_set_event_handler(VeloopHostWatcher, ^{
        NSUInteger generation = ++VeloopHostCheckGeneration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), queue, ^{
            if (generation == VeloopHostCheckGeneration) {
                VeloopCheckHost();
            }
        });
    });
    dispatch_resume(VeloopHostWatcher);
    dispatch_async(queue, ^{ VeloopCheckHost(); });
}

@interface VeloopPaletteController : IMKInputController
@property(nonatomic, assign, getter=isActive) BOOL active;
@property(nonatomic, assign) NSUInteger activationGeneration;
@property(nonatomic, copy) NSString *registeredBundleIdentifier;
@end

static NSMapTable<NSString *, NSHashTable<VeloopPaletteController *> *> *VeloopControllers;
static NSUInteger VeloopControllerGeneration;

static void VeloopRegisterController(
    NSString *bundleIdentifier,
    VeloopPaletteController *controller
) {
    if (bundleIdentifier.length == 0 || controller == nil) {
        return;
    }
    @synchronized (VeloopControllers) {
        NSHashTable<VeloopPaletteController *> *controllers =
            [VeloopControllers objectForKey:bundleIdentifier];
        if (controllers == nil) {
            controllers = [NSHashTable weakObjectsHashTable];
            [VeloopControllers setObject:controllers forKey:bundleIdentifier];
        }
        controller.activationGeneration = ++VeloopControllerGeneration;
        [controllers addObject:controller];
    }
}

static void VeloopUnregisterController(
    NSString *bundleIdentifier,
    VeloopPaletteController *controller
) {
    if (bundleIdentifier.length == 0 || controller == nil) {
        return;
    }
    @synchronized (VeloopControllers) {
        NSHashTable<VeloopPaletteController *> *controllers =
            [VeloopControllers objectForKey:bundleIdentifier];
        [controllers removeObject:controller];
        if (controllers.count == 0) {
            [VeloopControllers removeObjectForKey:bundleIdentifier];
        }
    }
}

static NSArray<VeloopPaletteController *> *VeloopActiveControllersForBundle(
    NSString *bundleIdentifier
) {
    @synchronized (VeloopControllers) {
        NSArray<VeloopPaletteController *> *controllers =
            [[VeloopControllers objectForKey:bundleIdentifier] allObjects];
        return [controllers sortedArrayUsingComparator:^NSComparisonResult(
            VeloopPaletteController *left,
            VeloopPaletteController *right
        ) {
            if (left.activationGeneration > right.activationGeneration) {
                return NSOrderedAscending;
            }
            if (left.activationGeneration < right.activationGeneration) {
                return NSOrderedDescending;
            }
            return NSOrderedSame;
        }];
    }
}

static BOOL VeloopIsCaretRect(NSRect rect) {
    return isfinite(rect.origin.x)
        && isfinite(rect.origin.y)
        && isfinite(rect.size.width)
        && isfinite(rect.size.height)
        && rect.size.width >= 0
        && rect.size.width <= 8
        && rect.size.height >= 4
        && rect.size.height <= 160;
}

static NSDictionary *VeloopResponse(
    NSString *bundleIdentifier,
    pid_t processIdentifier,
    NSRect rect,
    NSString *source
) {
    return @{
        @"bundleIdentifier": bundleIdentifier,
        @"processIdentifier": @(processIdentifier),
        @"x": @(rect.origin.x),
        @"y": @(rect.origin.y),
        @"width": @(rect.size.width),
        @"height": @(rect.size.height),
        @"source": source,
    };
}

@implementation VeloopPaletteController

+ (void)initialize {
    if (self == VeloopPaletteController.class) {
        VeloopControllers = [NSMapTable strongToStrongObjectsMapTable];
    }
}

- (void)activateServer:(id)sender {
    self.active = YES;
    NSString *clientBundle = [self.client bundleIdentifier];
    if (self.registeredBundleIdentifier.length > 0
        && ![self.registeredBundleIdentifier isEqualToString:clientBundle]) {
        VeloopUnregisterController(self.registeredBundleIdentifier, self);
    }
    self.registeredBundleIdentifier = clientBundle;
    VeloopRegisterController(clientBundle, self);
    [super activateServer:sender];
}

- (void)deactivateServer:(id)sender {
    self.active = NO;
    VeloopUnregisterController(self.registeredBundleIdentifier, self);
    self.registeredBundleIdentifier = nil;
    [super deactivateServer:sender];
}

- (void)inputControllerWillClose {
    self.active = NO;
    VeloopUnregisterController(self.registeredBundleIdentifier, self);
    self.registeredBundleIdentifier = nil;
    [super inputControllerWillClose];
}

- (NSDictionary *)caretResponseForBundle:(NSString *)requestedBundle
                        processIdentifier:(pid_t)requestedProcessIdentifier {
    if (!self.isActive) {
        return nil;
    }
    id<IMKTextInput, NSObject> client = self.client;
    NSString *clientBundle = [client bundleIdentifier] ?: @"";
    if (![clientBundle isEqual:requestedBundle]) {
        return nil;
    }

    NSRange selection = NSMakeRange(NSNotFound, 0);
    @try {
        selection = [client selectedRange];
    } @catch (__unused NSException *exception) {
        return nil;
    }
    if (selection.location == NSNotFound || selection.length != 0) {
        return nil;
    }

    @try {
        NSRect lineRect = NSZeroRect;
        [client attributesForCharacterIndex:selection.location lineHeightRectangle:&lineRect];
        if (VeloopIsCaretRect(lineRect)) {
            return VeloopResponse(
                clientBundle,
                requestedProcessIdentifier,
                lineRect,
                @"paletteLineRectangle"
            );
        }
    } @catch (__unused NSException *exception) {
    }

    @try {
        NSRange actualRange = NSMakeRange(NSNotFound, 0);
        NSRect rangeRect = [client
            firstRectForCharacterRange:NSMakeRange(selection.location, 0)
            actualRange:&actualRange];
        if (VeloopIsCaretRect(rangeRect)) {
            return VeloopResponse(
                clientBundle,
                requestedProcessIdentifier,
                rangeRect,
                @"paletteRangeRectangle"
            );
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

@end

static CFDataRef VeloopHandleCaretRequest(
    __unused CFMessagePortRef local,
    SInt32 messageIdentifier,
    CFDataRef data,
    __unused void *info
) {
    @autoreleasepool {
        if (messageIdentifier != 1
            || data == nil
            || CFDataGetLength(data) > VeloopMaximumMessageBytes) {
            return nil;
        }
        NSError *error = nil;
        NSDictionary *request = [NSPropertyListSerialization
            propertyListWithData:(__bridge NSData *)data
            options:NSPropertyListImmutable
            format:nil
            error:&error];
        id requestedBundleValue = [request isKindOfClass:NSDictionary.class]
            ? request[@"bundleIdentifier"]
            : nil;
        id requestedProcessIdentifierValue = [request isKindOfClass:NSDictionary.class]
            ? request[@"processIdentifier"]
            : nil;
        if (error != nil
            || ![requestedBundleValue isKindOfClass:NSString.class]
            || ![requestedProcessIdentifierValue isKindOfClass:NSNumber.class]) {
            return nil;
        }
        NSString *requestedBundle = requestedBundleValue;
        NSNumber *requestedProcessIdentifier = requestedProcessIdentifierValue;
        NSRunningApplication *frontmostApplication = NSWorkspace.sharedWorkspace.frontmostApplication;
        if (requestedBundle.length == 0
            || requestedProcessIdentifier.intValue <= 0
            || frontmostApplication.processIdentifier != requestedProcessIdentifier.intValue
            || ![requestedBundle isEqualToString:frontmostApplication.bundleIdentifier]) {
            return nil;
        }

        NSDictionary *response = nil;
        NSArray<VeloopPaletteController *> *controllers =
            VeloopActiveControllersForBundle(requestedBundle);
        for (VeloopPaletteController *controller in controllers) {
            response = [controller
                caretResponseForBundle:requestedBundle
                processIdentifier:requestedProcessIdentifier.intValue];
            if (response != nil) {
                break;
            }
        }
        if (response == nil) {
            return nil;
        }
        NSData *responseData = [NSPropertyListSerialization
            dataWithPropertyList:response
            format:NSPropertyListBinaryFormat_v1_0
            options:0
            error:&error];
        return error == nil && responseData.length <= VeloopMaximumMessageBytes
            ? CFBridgingRetain(responseData)
            : nil;
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        VeloopHostQueue = dispatch_queue_create(
            "com.veloop.palette.host-watcher",
            DISPATCH_QUEUE_SERIAL
        );
        IMKServer *server = [[IMKServer alloc]
            initWithName:@"com_talentdedcat_veloop_palette_connection"
            bundleIdentifier:@"com.talentdedcat.veloop.palette"];
        if (server == nil) {
            return 1;
        }

        CFMessagePortRef port = CFMessagePortCreateLocal(
            kCFAllocatorDefault,
            (__bridge CFStringRef)VeloopCaretPortName,
            VeloopHandleCaretRequest,
            NULL,
            NULL
        );
        if (port == nil) {
            return 2;
        }
        CFRunLoopSourceRef source = CFMessagePortCreateRunLoopSource(
            kCFAllocatorDefault,
            port,
            0
        );
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
        VeloopStartHostWatcher();
        CFRunLoopRun();
        CFRelease(source);
        CFRelease(port);
    }
    return 0;
}
