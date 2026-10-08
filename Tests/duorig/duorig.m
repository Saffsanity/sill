// duorig — TEST ONLY. Folds and turns an iPhone Duo in the iOS Simulator from the command line, as
// Xcode 27.1's Device Hub does with its hinge slider and orientation picker, so the Duo's poses can
// be driven and photographed with no hand on Device Hub (docs/iphone-duo-plan.md, Facts).
//
// PRIVATE INTERFACES, SIMULATOR ONLY. It uses HID.framework's HIDVirtualEventService and IOKit's
// IOHIDEvent calls (dlopen/dlsym, no headers), and posts into the HID event system of the simulator
// it runs in (the simulated backboardd's com.apple.iohideventsystem). It is never part of Sill, never
// built for a device, and refuses to run outside a simulator (no SIMULATOR_UDID/SIMULATOR_ROOT).
// Build and run it only through Tests/duorig/run.sh, which uses `xcrun simctl spawn`.
//
// What Device Hub sends (read from CoreDevicePopDeviceKitExtension, Xcode 27.1 27A9275): one
// vendor-defined HID event, HIDVendorDefined.send(usagePage: 0xFF61, usage: 0x5B, version: 0, data:),
// whose data is IOCFSerialize(dictionary, kIOCFSerializeToBinary) of
//   hinge:       provider "com.apple.Virtualization.VirtualMachines", source "hinge-slider-control",
//                type "range", value <degrees, a Double clamped to 0...180: 0 closed, 180 flat>
//   orientation: provider "com.apple.Virtualization.VirtualMachines", source "orientation-picker-control",
//                type "enum", value "portrait" | "pud" | "landscape-left" | "landscape-right" |
//                "faceup" | "facedown"
// CoreDevice hands it to the simulator's dtuhidd, which dispatches it from a virtual HID service. Here
// the virtual service is our own (usage pair 0xFF61/0x5B); the simulator's CoreMotion
// (CoreMotion_DeviceStateRelay_*) turns the hinge event into a HingeAngle event (IOHIDEvent type 44)
// and the orientation into a MagicPose, and SpringBoard moves the app between the displays.
//
//   duorig services                          list this simulator's HID services (read-only)
//   duorig watch [seconds]                   print every event the event system routes (read-only)
//   duorig hinge <degrees> [hold]            post a hinge angle
//   duorig orient <orientation> [hold]       post a device orientation
//   duorig pose <degrees> <orientation> [hold]   both, hinge first
//   duorig sweep <from> <to> <step> <interval> [hold]
//
// `hold` is how long (seconds, default 0.5) the virtual service stays after the last event; the
// simulator keeps the last angle and orientation once it has gone.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach/mach_time.h>

typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;

static void *iokit;

typedef IOHIDEventSystemClientRef (*CreateWithType_t)(CFAllocatorRef, int, CFDictionaryRef);
typedef CFArrayRef (*CopyServices_t)(IOHIDEventSystemClientRef);
typedef CFTypeRef (*SvcCopyProp_t)(IOHIDServiceClientRef, CFStringRef);
typedef CFTypeRef (*SvcGetRegID_t)(IOHIDServiceClientRef);
typedef IOHIDEventRef (*CreateVendor_t)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
                                        const uint8_t *, CFIndex, uint32_t);
typedef CFDataRef (*IOCFSerialize_t)(CFTypeRef, uint32_t);
typedef void (*RegisterCB_t)(IOHIDEventSystemClientRef, void *, void *, void *);
typedef void (*ScheduleQ_t)(IOHIDEventSystemClientRef, dispatch_queue_t);
typedef int (*EventGetType_t)(IOHIDEventRef);
typedef uint64_t (*EventGetSender_t)(IOHIDEventRef);

static void *sym(const char *name) {
    void *p = dlsym(iokit, name);
    if (!p) { fprintf(stderr, "duorig: %s is missing from this simulator's IOKit\n", name); exit(2); }
    return p;
}

static void out(NSString *s) {
    fprintf(stdout, "%s\n", s.UTF8String);
    fflush(stdout);
}

static NSString *oneLine(NSString *s) {
    return [[s componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
}

/// Inside a simulator launchd_sim sets SIMULATOR_UDID and SIMULATOR_ROOT (and the simulator's
/// IOKit is the simulator's); anywhere else this refuses before touching any HID interface.
static void requireSimulator(void) {
    const char *udid = getenv("SIMULATOR_UDID");
    const char *root = getenv("SIMULATOR_ROOT");
    if (!udid || !root || !*udid || !*root) {
        out(@"duorig: refused: not inside an iOS Simulator. Run it with Tests/duorig/run.sh (xcrun simctl spawn).");
        exit(3);
    }
    iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    if (!iokit) { out(@"duorig: IOKit did not load"); exit(2); }
    if (!dlopen("/System/Library/PrivateFrameworks/HID.framework/HID", RTLD_NOW)) {
        out(@"duorig: HID.framework did not load"); exit(2);
    }
}

static int listServices(void) {
    CreateWithType_t create = (CreateWithType_t)sym("IOHIDEventSystemClientCreateWithType");
    CopyServices_t copy = (CopyServices_t)sym("IOHIDEventSystemClientCopyServices");
    SvcCopyProp_t copyProp = (SvcCopyProp_t)sym("IOHIDServiceClientCopyProperty");
    SvcGetRegID_t regID = (SvcGetRegID_t)sym("IOHIDServiceClientGetRegistryID");
    IOHIDEventSystemClientRef client = create(kCFAllocatorDefault, 0 /* admin */, NULL);
    if (!client) { out(@"duorig: no event system client"); return 1; }
    NSArray *services = (__bridge_transfer NSArray *)copy(client);
    out([NSString stringWithFormat:@"duorig: %lu HID services in simulator %s", (unsigned long)services.count, getenv("SIMULATOR_UDID")]);
    for (id obj in services) {
        IOHIDServiceClientRef svc = (__bridge IOHIDServiceClientRef)obj;
        NSMutableString *line = [NSMutableString stringWithFormat:@"  id %@", (__bridge id)regID(svc)];
        for (NSString *key in @[@"PrimaryUsagePage", @"PrimaryUsage", @"Product", @"Transport", @"Built-In"]) {
            CFTypeRef v = copyProp(svc, (__bridge CFStringRef)key);
            if (!v) continue;
            id value = (__bridge_transfer id)v;
            NSString *text = [key hasPrefix:@"Primary"] && [value isKindOfClass:[NSNumber class]]
                ? [NSString stringWithFormat:@"0x%lx", (unsigned long)[value unsignedIntegerValue]] : oneLine([value description]);
            [line appendFormat:@" %@=%@", key, text];
        }
        out(line);
    }
    CFRelease(client);
    return 0;
}

static void watchCallback(void *target, void *refcon, IOHIDServiceClientRef sender, IOHIDEventRef event) {
    static EventGetType_t getType;
    static EventGetSender_t getSender;
    if (!getType) { getType = (EventGetType_t)sym("IOHIDEventGetType"); getSender = (EventGetSender_t)sym("IOHIDEventGetSenderID"); }
    NSString *desc = @"";
    CFStringRef d = CFCopyDescription(event);
    if (d) desc = oneLine((__bridge_transfer NSString *)d);
    if (desc.length > 700) desc = [[desc substringToIndex:700] stringByAppendingString:@"…"];
    out([NSString stringWithFormat:@"event type %d sender 0x%llx %@", getType(event), getSender(event), desc]);
}

static int watch(double seconds) {
    CreateWithType_t create = (CreateWithType_t)sym("IOHIDEventSystemClientCreateWithType");
    IOHIDEventSystemClientRef client = create(kCFAllocatorDefault, 1 /* monitor */, NULL);
    if (!client) { out(@"duorig: no monitor client"); return 1; }
    ((RegisterCB_t)sym("IOHIDEventSystemClientRegisterEventCallback"))(client, (void *)watchCallback, NULL, NULL);
    ((ScheduleQ_t)sym("IOHIDEventSystemClientScheduleWithDispatchQueue"))(client, dispatch_get_main_queue());
    out([NSString stringWithFormat:@"duorig: watching for %.0f s", seconds]);
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
    return 0;
}

/// HIDVirtualEventService's delegate (the protocol is not registered in the runtime, so these are
/// its selectors by name): the service's properties, nothing else.
@interface DuoRigDelegate : NSObject
@end

@implementation DuoRigDelegate
- (BOOL)setProperty:(id)value forKey:(NSString *)key forService:(id)service { return NO; }
- (id)propertyForKey:(NSString *)key forService:(id)service {
    static NSDictionary *properties;
    if (!properties) {
        properties = @{ @"PrimaryUsagePage": @(0xFF61), @"PrimaryUsage": @(0x5B),
                        @"DeviceUsagePairs": @[ @{ @"DeviceUsagePage": @(0xFF61), @"DeviceUsage": @(0x5B) } ],
                        @"Product": @"duorig (TEST ONLY)", @"Transport": @"Virtual",
                        @"Built-In": @YES, @"HIDVirtualDevice": @YES };
    }
    return properties[key];
}
- (id)copyEventMatching:(NSDictionary *)matching forService:(id)service { return nil; }
- (BOOL)setOutputEvent:(id)event forService:(id)service { return NO; }
- (void)notification:(NSInteger)type withProperty:(NSDictionary *)property forService:(id)service {}
@end

static IOHIDEventRef vendorEvent(NSDictionary *dict) {
    CFDataRef data = ((IOCFSerialize_t)sym("IOCFSerialize"))((__bridge CFTypeRef)dict, 1 /* kIOCFSerializeToBinary */);
    if (!data) { out(@"duorig: IOCFSerialize failed"); exit(1); }
    IOHIDEventRef event = ((CreateVendor_t)sym("IOHIDEventCreateVendorDefinedEvent"))(
        kCFAllocatorDefault, mach_absolute_time(), 0xFF61, 0x5B, 0, CFDataGetBytePtr(data), CFDataGetLength(data), 0);
    CFRelease(data);
    if (!event) { out(@"duorig: the event was not made"); exit(1); }
    return event;
}

static IOHIDEventRef hingeEvent(double degrees) {
    degrees = fmin(fmax(degrees, 0), 180);
    return vendorEvent(@{ @"provider": @"com.apple.Virtualization.VirtualMachines",
                          @"source": @"hinge-slider-control", @"type": @"range", @"value": @(degrees) });
}

static IOHIDEventRef orientationEvent(NSString *value) {
    return vendorEvent(@{ @"provider": @"com.apple.Virtualization.VirtualMachines",
                          @"source": @"orientation-picker-control", @"type": @"enum", @"value": value });
}

static NSArray<NSString *> *orientations(void) {
    return @[@"portrait", @"pud", @"landscape-left", @"landscape-right", @"faceup", @"facedown"];
}

/// One virtual service for the run: the events in order, `interval` apart, then `hold` seconds.
static int post(NSArray *events, NSArray<NSString *> *labels, double interval, double hold) {
    Class cls = objc_getClass("HIDVirtualEventService");
    if (!cls) { out(@"duorig: no HIDVirtualEventService in this simulator"); return 1; }
    DuoRigDelegate *delegate = [DuoRigDelegate new];
    id service = ((id (*)(id, SEL))objc_msgSend)([cls alloc], sel_registerName("init"));
    if (!service) { out(@"duorig: the virtual service was not made"); return 1; }
    ((void (*)(id, SEL, id))objc_msgSend)(service, sel_registerName("setDelegate:"), delegate);
    ((void (*)(id, SEL, dispatch_queue_t))objc_msgSend)(service, sel_registerName("setDispatchQueue:"), dispatch_get_main_queue());
    ((void (*)(id, SEL))objc_msgSend)(service, sel_registerName("activate"));
    // The event system enumerates the new service before it routes its events.
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
    int failures = 0;
    for (NSUInteger i = 0; i < events.count; i++) {
        BOOL ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(service, sel_registerName("dispatchEvent:"), events[i]);
        out([NSString stringWithFormat:@"duorig: %@%@", labels[i], ok ? @"" : @" NOT dispatched"]);
        if (!ok) failures++;
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:interval]];
    }
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:hold]];
    ((void (*)(id, SEL))objc_msgSend)(service, sel_registerName("cancel"));
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    return failures ? 1 : 0;
}

static int usage(void) {
    out(@"usage: duorig services | watch [s] | hinge <0-180> [hold] | orient <portrait|pud|landscape-left|"
        @"landscape-right|faceup|facedown> [hold] | pose <0-180> <orientation> [hold] | "
        @"sweep <from> <to> <step> <interval> [hold]");
    return 2;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        requireSimulator();
        NSString *cmd = argc > 1 ? @(argv[1]) : @"";
        if ([cmd isEqualToString:@"services"]) return listServices();
        if ([cmd isEqualToString:@"watch"]) return watch(argc > 2 ? atof(argv[2]) : 10);
        if ([cmd isEqualToString:@"hinge"] && argc > 2) {
            double a = atof(argv[2]);
            return post(@[(__bridge_transfer id)hingeEvent(a)], @[[NSString stringWithFormat:@"hinge %.1f°", a]],
                        0, argc > 3 ? atof(argv[3]) : 0.5);
        }
        if ([cmd isEqualToString:@"orient"] && argc > 2) {
            NSString *o = @(argv[2]);
            if (![orientations() containsObject:o]) return usage();
            return post(@[(__bridge_transfer id)orientationEvent(o)], @[[@"orientation " stringByAppendingString:o]],
                        0, argc > 3 ? atof(argv[3]) : 0.5);
        }
        if ([cmd isEqualToString:@"pose"] && argc > 3) {
            double a = atof(argv[2]);
            NSString *o = @(argv[3]);
            if (![orientations() containsObject:o]) return usage();
            return post(@[(__bridge_transfer id)hingeEvent(a), (__bridge_transfer id)orientationEvent(o)],
                        @[[NSString stringWithFormat:@"hinge %.1f°", a], [@"orientation " stringByAppendingString:o]],
                        1.0, argc > 4 ? atof(argv[4]) : 0.5);
        }
        if ([cmd isEqualToString:@"sweep"] && argc > 5) {
            double from = atof(argv[2]), to = atof(argv[3]), step = fabs(atof(argv[4])), interval = atof(argv[5]);
            if (step <= 0) return usage();
            NSMutableArray *events = [NSMutableArray array];
            NSMutableArray *labels = [NSMutableArray array];
            for (double a = from; to >= from ? a <= to + 1e-9 : a >= to - 1e-9; a += to >= from ? step : -step) {
                [events addObject:(__bridge_transfer id)hingeEvent(a)];
                [labels addObject:[NSString stringWithFormat:@"hinge %.1f°", a]];
            }
            return post(events, labels, interval, argc > 6 ? atof(argv[6]) : 0.5);
        }
        return usage();
    }
}
