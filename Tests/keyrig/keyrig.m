// keyrig — TEST ONLY. A hardware keyboard and a mouse for the iOS Simulator, from the command line: key
// presses, pointer moves and wheel scrolls posted from a virtual HID service of its own inside the
// simulator it runs in, so UIKit routes them as it routes a real keyboard's and mouse's (pressesBegan,
// key commands, the text system, GameController, hover and scroll events), with no hand on the Simulator
// app and nothing posted on the Mac (docs/hardware-keyboard-plan.md, Results).
//
// PRIVATE INTERFACES, SIMULATOR ONLY, as Tests/duorig: HID.framework's HIDVirtualEventService and
// IOKit's IOHIDEvent calls through dlopen/dlsym, posting into the HID event system of the simulator it
// runs in (the simulated backboardd's). It is never part of Sill, never built for a device, and refuses
// to run outside a simulator (no SIMULATOR_UDID/SIMULATOR_ROOT). Run it only through Tests/keyrig/run.sh,
// which uses `xcrun simctl spawn`.
//
//   keyrig keys <spec> [settle] [hold]     spec: USAGE[:down|:up],… in hex (HID page 7): a bare USAGE is a
//                                          press (down, 60 ms, up); steps 250 ms apart. 29 is Esc, e3 ⌘.
//   keyrig point <script> [settle] [hold]  script: steps separated by ; or |: move DX,DY (a relative
//                                          pointer move), wheel DY (one scroll event, lines), phase
//                                          began|changed|ended DX,DY (a scroll event with that phase),
//                                          momentum BITS DY (a scroll event marked as momentum, the bits
//                                          in hex: 2 start, 1 continue, 4 end), wait S
//
// `settle` (default 0.6 s) is how long the new service is left before its first event (the event system
// enumerates it first); `hold` (default 0.3 s) how long it stays after its last.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach/mach_time.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef IOHIDEventRef (*CreateKeyboard_t)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, Boolean, uint32_t);
typedef IOHIDEventRef (*CreateRelative_t)(CFAllocatorRef, uint64_t, double, double, double, uint32_t, uint32_t);
typedef IOHIDEventRef (*CreateScroll_t)(CFAllocatorRef, uint64_t, double, double, double, uint32_t);
typedef void (*SetPhase_t)(IOHIDEventRef, uint16_t);
typedef void (*SetMomentum_t)(IOHIDEventRef, uint8_t);

static void *iokit;

static void out(NSString *s) {
    fprintf(stdout, "%s\n", s.UTF8String);
    fflush(stdout);
}

static void *sym(const char *name) {
    void *p = dlsym(iokit, name);
    if (!p) { out([NSString stringWithFormat:@"keyrig: %s is missing from this simulator's IOKit", name]); exit(2); }
    return p;
}

/// Inside a simulator launchd_sim sets SIMULATOR_UDID and SIMULATOR_ROOT; anywhere else this refuses
/// before touching any HID interface.
static void requireSimulator(void) {
    const char *udid = getenv("SIMULATOR_UDID");
    const char *root = getenv("SIMULATOR_ROOT");
    if (!udid || !root || !*udid || !*root) {
        out(@"keyrig: refused: not inside an iOS Simulator. Run it with Tests/keyrig/run.sh (xcrun simctl spawn).");
        exit(3);
    }
    iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (!iokit) { out(@"keyrig: IOKit did not load"); exit(2); }
    if (!dlopen("/System/Library/PrivateFrameworks/HID.framework/HID", RTLD_NOW)) { out(@"keyrig: HID.framework did not load"); exit(2); }
}

/// HIDVirtualEventService's delegate (the protocol is not registered in the runtime, so these are its
/// selectors by name): the service's properties, nothing else.
@interface KeyRigDelegate : NSObject
@property (nonatomic, copy) NSDictionary *properties;
@end

@implementation KeyRigDelegate
- (BOOL)setProperty:(id)value forKey:(NSString *)key forService:(id)service { return NO; }
- (id)propertyForKey:(NSString *)key forService:(id)service { return self.properties[key]; }
- (id)copyEventMatching:(NSDictionary *)matching forService:(id)service { return nil; }
- (BOOL)setOutputEvent:(id)event forService:(id)service { return NO; }
- (void)notification:(NSInteger)type withProperty:(NSDictionary *)property forService:(id)service {}
@end

static void spin(double seconds) {
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

/// A virtual service with these usage pairs, up for the run; dispatch with `dispatch`.
static id startService(KeyRigDelegate *delegate, double settle) {
    Class cls = objc_getClass("HIDVirtualEventService");
    if (!cls) { out(@"keyrig: no HIDVirtualEventService in this simulator"); exit(1); }
    id service = ((id (*)(id, SEL))objc_msgSend)([cls alloc], sel_registerName("init"));
    if (!service) { out(@"keyrig: the virtual service was not made"); exit(1); }
    ((void (*)(id, SEL, id))objc_msgSend)(service, sel_registerName("setDelegate:"), delegate);
    ((void (*)(id, SEL, dispatch_queue_t))objc_msgSend)(service, sel_registerName("setDispatchQueue:"), dispatch_get_main_queue());
    ((void (*)(id, SEL))objc_msgSend)(service, sel_registerName("activate"));
    spin(settle);
    return service;
}

static BOOL dispatchEvent(id service, IOHIDEventRef event) {
    BOOL ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(service, sel_registerName("dispatchEvent:"), (__bridge id)event);
    CFRelease(event);
    return ok;
}

static void stopService(id service, double hold) {
    spin(hold);
    ((void (*)(id, SEL))objc_msgSend)(service, sel_registerName("cancel"));
    spin(0.1);
}

static int keys(NSString *spec, double settle, double hold) {
    CreateKeyboard_t create = (CreateKeyboard_t)sym("IOHIDEventCreateKeyboardEvent");
    KeyRigDelegate *delegate = [KeyRigDelegate new];
    delegate.properties = @{ @"PrimaryUsagePage": @1, @"PrimaryUsage": @6,
                             @"DeviceUsagePairs": @[ @{ @"DeviceUsagePage": @1, @"DeviceUsage": @6 } ],
                             @"Product": @"keyrig keyboard (TEST ONLY)", @"Transport": @"Bluetooth", @"Built-In": @NO,
                             @"CountryCode": @0, @"StandardType": @0, @"HIDVirtualDevice": @YES };
    id service = startService(delegate, settle);
    int failures = 0;
    for (NSString *step in [spec componentsSeparatedByString:@","]) {
        NSArray *parts = [step componentsSeparatedByString:@":"];
        unsigned usage = 0;
        if (![[NSScanner scannerWithString:parts[0]] scanHexInt:&usage]) { out([@"keyrig: cannot read " stringByAppendingString:step]); failures++; continue; }
        NSArray *phases = parts.count > 1 ? @[@([parts[1] isEqualToString:@"down"])] : @[@YES, @NO];
        for (NSNumber *down in phases) {
            BOOL ok = dispatchEvent(service, create(kCFAllocatorDefault, mach_absolute_time(), 7, usage, down.boolValue, 0));
            out([NSString stringWithFormat:@"keyrig: usage 0x%x %@%@", usage, down.boolValue ? @"down" : @"up", ok ? @"" : @" NOT dispatched"]);
            if (!ok) failures++;
            spin(0.06);
        }
        spin(0.25);
    }
    stopService(service, hold);
    return failures ? 1 : 0;
}

static int point(NSString *script, double settle, double hold) {
    CreateRelative_t move = (CreateRelative_t)sym("IOHIDEventCreateRelativePointerEvent");
    CreateScroll_t scroll = (CreateScroll_t)sym("IOHIDEventCreateScrollEvent");
    KeyRigDelegate *delegate = [KeyRigDelegate new];
    delegate.properties = @{ @"PrimaryUsagePage": @1, @"PrimaryUsage": @2,
                             @"DeviceUsagePairs": @[ @{ @"DeviceUsagePage": @1, @"DeviceUsage": @2 },
                                                     @{ @"DeviceUsagePage": @1, @"DeviceUsage": @1 } ],
                             @"Product": @"keyrig mouse (TEST ONLY)", @"Transport": @"Bluetooth", @"Built-In": @NO,
                             @"HIDVirtualDevice": @YES };
    id service = startService(delegate, settle);
    int failures = 0;
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@";|"];
    for (NSString *raw in [script componentsSeparatedByCharactersInSet:separators]) {
        NSString *step = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (step.length == 0) continue;
        NSArray *words = [step componentsSeparatedByString:@" "];
        NSArray *numbers = words.count > 1 ? [words.lastObject componentsSeparatedByString:@","] : @[];
        double a = numbers.count > 0 ? [numbers[0] doubleValue] : 0, b = numbers.count > 1 ? [numbers[1] doubleValue] : 0;
        IOHIDEventRef event = NULL;
        if ([words[0] isEqualToString:@"wait"]) { spin(a); continue; }
        if ([words[0] isEqualToString:@"move"] && numbers.count == 2) event = move(kCFAllocatorDefault, mach_absolute_time(), a, b, 0, 0, 0);
        else if ([words[0] isEqualToString:@"wheel"] && numbers.count == 1) event = scroll(kCFAllocatorDefault, mach_absolute_time(), 0, a, 0, 0);
        else if ([words[0] isEqualToString:@"phase"] && words.count == 3 && numbers.count == 2) {
            NSDictionary *bits = @{ @"began": @1, @"changed": @2, @"ended": @4 };
            if (bits[words[1]]) {
                event = scroll(kCFAllocatorDefault, mach_absolute_time(), a, b, 0, 0);
                ((SetPhase_t)sym("IOHIDEventSetPhase"))(event, [bits[words[1]] unsignedShortValue]);
            }
        } else if ([words[0] isEqualToString:@"momentum"] && words.count == 3 && numbers.count == 1) {
            unsigned bits = 0;
            if ([[NSScanner scannerWithString:words[1]] scanHexInt:&bits]) {
                event = scroll(kCFAllocatorDefault, mach_absolute_time(), 0, a, 0, 0);
                ((SetMomentum_t)sym("IOHIDEventSetScrollMomentum"))(event, (uint8_t)bits);
            }
        }
        if (!event) { out([@"keyrig: cannot read " stringByAppendingString:step]); failures++; continue; }
        BOOL ok = dispatchEvent(service, event);
        out([NSString stringWithFormat:@"keyrig: %@%@", step, ok ? @"" : @" NOT dispatched"]);
        if (!ok) failures++;
        spin(0.016);
    }
    stopService(service, hold);
    return failures ? 1 : 0;
}

static int usage(void) {
    out(@"usage: keyrig keys <USAGE[:down|:up],…> [settle] [hold] | point <move DX,DY|wheel DY|phase P DX,DY|momentum BITS DY|wait S;…> [settle] [hold]");
    return 2;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        requireSimulator();
        if (argc < 3) return usage();
        NSString *cmd = @(argv[1]);
        double settle = argc > 3 ? atof(argv[3]) : 0.6, hold = argc > 4 ? atof(argv[4]) : 0.3;
        if ([cmd isEqualToString:@"keys"]) return keys(@(argv[2]), settle, hold);
        if ([cmd isEqualToString:@"point"]) return point(@(argv[2]), settle, hold);
        return usage();
    }
}
