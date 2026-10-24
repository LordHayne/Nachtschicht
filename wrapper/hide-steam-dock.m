// Keeps Steam's own processes out of the Dock when Nachtschicht runs it in the background.
//
// Wine turns a process into a regular Dock app as soon as it shows any window. Steam's browser
// (steamwebhelper) does that even with -silent, for tiny invisible menu windows. This library is
// loaded into Wine processes via DYLD_INSERT_LIBRARIES and downgrades that request to an accessory
// app – only for Steam's processes, so its dialogs still appear but no Dock icon does. Games keep
// their normal Dock icon.
//
// With Game Mode on, Wine runs from an app bundle (see Engine.installGameBundle), and macOS makes every
// process started from a bundle a Dock app right away, without asking setActivationPolicy:. So
// all of them start as accessory apps, and only a process that shows a window (a game) gets one.
//
// Build (x86_64, like Wine): clang -arch x86_64 -dynamiclib -framework AppKit -o hide-steam-dock.dylib hide-steam-dock.m

#import <AppKit/AppKit.h>
#import <crt_externs.h>
#import <objc/runtime.h>

static BOOL isSteamProcess(void) {
    // Wine rewrites argv[0] to the Windows path of the program it's running.
    char **argv = *_NSGetArgv();
    if (!argv || !argv[0]) return NO;
    NSString *program = [@(argv[0]) lowercaseString];
    return [program containsString:@"steamwebhelper"]
        || [program hasSuffix:@"\\steam\\steam.exe"]
        || [program containsString:@"steamservice"];
}

static BOOL (*originalSetActivationPolicy)(id, SEL, NSApplicationActivationPolicy);
static BOOL wantsDock = NO;

static BOOL nachtschichtSetActivationPolicy(id self, SEL _cmd, NSApplicationActivationPolicy policy) {
    if (policy == NSApplicationActivationPolicyRegular) {
        if (isSteamProcess()) policy = NSApplicationActivationPolicyAccessory;
        else wantsDock = YES;
    }
    return originalSetActivationPolicy(self, _cmd, policy);
}

__attribute__((constructor)) static void install(void) {
    Method method = class_getInstanceMethod([NSApplication class], @selector(setActivationPolicy:));
    if (!method) return;
    originalSetActivationPolicy = (void *)method_setImplementation(method, (IMP)nachtschichtSetActivationPolicy);

    // Started from the bundle, every Wine process – Steam, explorer.exe, services – would be a Dock
    // app from the start. Make them accessory apps until Wine itself asks for a Dock icon, which it
    // does when a game shows its window (Steam's requests are turned down above).
    for (NSNotificationName name in @[NSApplicationWillFinishLaunchingNotification, NSApplicationDidFinishLaunchingNotification]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            if (!wantsDock && [NSApp activationPolicy] == NSApplicationActivationPolicyRegular) {
                originalSetActivationPolicy(NSApp, @selector(setActivationPolicy:), NSApplicationActivationPolicyAccessory);
            }
        }];
    }
}
