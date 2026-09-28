// TEST ONLY (Tests/touchrig, never in the app or on a device). KIF-style in-process touch synthesis
// for the iOS simulator: UITouch and UIEvent private setters plus an IOHIDEvent digitizer event
// (UIKit's gesture environment reads it since iOS 9). On iOS 27 `setGestureView:` and `setIsTap:` are
// gone; they are skipped when missing.
#import "TouchSynth.h"
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <objc/message.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef double IOHIDFloat;
typedef uint32_t IOOptionBits;
typedef uint32_t IOHIDEventField;

#define kIOHIDEventTypeDigitizer 11
#define IOHIDEventFieldBase(type) ((type) << 16)
enum { kTransducerHand = 3 };
enum { kEventRange = 1 << 0, kEventTouch = 1 << 1, kEventPosition = 1 << 2 };
static const IOHIDEventField kFieldIsDisplayIntegrated = IOHIDEventFieldBase(kIOHIDEventTypeDigitizer) + 25;

typedef IOHIDEventRef (*CreateHandFn)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t,
                                      IOHIDFloat, IOHIDFloat, IOHIDFloat, IOHIDFloat, IOHIDFloat,
                                      boolean_t, boolean_t, IOOptionBits);
typedef IOHIDEventRef (*CreateFingerFn)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
                                        IOHIDFloat, IOHIDFloat, IOHIDFloat, IOHIDFloat, IOHIDFloat,
                                        IOHIDFloat, IOHIDFloat, IOHIDFloat, IOHIDFloat, IOHIDFloat,
                                        boolean_t, boolean_t, IOOptionBits);
typedef void (*AppendFn)(IOHIDEventRef, IOHIDEventRef, IOOptionBits);
typedef void (*SetIntFn)(IOHIDEventRef, IOHIDEventField, CFIndex);
typedef void (*SetSenderFn)(IOHIDEventRef, uint64_t);

static CreateHandFn createHand;
static CreateFingerFn createFinger;
static AppendFn appendEvent;
static SetIntFn setInt;
static SetSenderFn setSender;

@interface UITouch (RigPrivate)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setGestureView:(UIView *)view;
- (void)setPhase:(UITouchPhase)phase;
- (void)setTapCount:(NSUInteger)count;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setIsTap:(BOOL)isTap;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)reset;
- (void)_setIsFirstTouchForView:(BOOL)first;
- (void)_setHidEvent:(IOHIDEventRef)event;
- (void)_setPathIndex:(unsigned char)index;
- (void)_setPathIdentity:(unsigned char)identity;
@end

@interface UIEvent (RigPrivate)
- (void)_clearTouches;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_setHIDEvent:(IOHIDEventRef)event;
@end

@interface UIApplication (RigPrivate)
- (UIEvent *)_touchesEvent;
- (void)_enqueueHIDEvent:(IOHIDEventRef)event;
@end

@interface RigTouch : NSObject
@property (nonatomic, strong) UITouch *touch;
@property (nonatomic) uint32_t pathIndex;
@property (nonatomic) CGPoint point;
@end
@implementation RigTouch
@end

@implementation TouchSynth {
    UIWindow *_window;
    NSMutableArray<RigTouch *> *_active;
    uint32_t _nextIndex;
}

+ (void)load {
    void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    (void)h;
    createHand = (CreateHandFn)dlsym(RTLD_DEFAULT, "IOHIDEventCreateDigitizerEvent");
    createFinger = (CreateFingerFn)dlsym(RTLD_DEFAULT, "IOHIDEventCreateDigitizerFingerEventWithQuality");
    appendEvent = (AppendFn)dlsym(RTLD_DEFAULT, "IOHIDEventAppendEvent");
    setInt = (SetIntFn)dlsym(RTLD_DEFAULT, "IOHIDEventSetIntegerValue");
    setSender = (SetSenderFn)dlsym(RTLD_DEFAULT, "IOHIDEventSetSenderID");
}

+ (NSString *)selfCheck {
    NSMutableArray *missing = [NSMutableArray array];
    if (!createHand) [missing addObject:@"IOHIDEventCreateDigitizerEvent"];
    if (!createFinger) [missing addObject:@"IOHIDEventCreateDigitizerFingerEventWithQuality"];
    if (!appendEvent) [missing addObject:@"IOHIDEventAppendEvent"];
    if (!setInt) [missing addObject:@"IOHIDEventSetIntegerValue"];
    if (!setSender) [missing addObject:@"IOHIDEventSetSenderID"];
    NSArray *touchSels = @[@"setWindow:", @"setView:", @"setGestureView:", @"setPhase:", @"setTapCount:",
                           @"setTimestamp:", @"setIsTap:", @"_setLocationInWindow:resetPrevious:",
                           @"_setIsFirstTouchForView:", @"_setHidEvent:", @"_setPathIndex:", @"_setPathIdentity:"];
    UITouch *t = [UITouch new];
    for (NSString *s in touchSels) if (![t respondsToSelector:NSSelectorFromString(s)]) [missing addObject:[@"UITouch " stringByAppendingString:s]];
    UIEvent *e = [[UIApplication sharedApplication] respondsToSelector:@selector(_touchesEvent)] ? [[UIApplication sharedApplication] _touchesEvent] : nil;
    if (!e) [missing addObject:@"UIApplication _touchesEvent"];
    for (NSString *s in @[@"_clearTouches", @"_addTouch:forDelayedDelivery:", @"_setHIDEvent:"])
        if (e && ![e respondsToSelector:NSSelectorFromString(s)]) [missing addObject:[@"UIEvent " stringByAppendingString:s]];
    NSMutableArray *routing = [NSMutableArray array];
    for (NSString *sel in @[@"_enqueueHIDEvent:", @"_handleHIDEvent:", @"_eventDispatcher", @"_hidEventFilter"])
        [routing addObject:[NSString stringWithFormat:@"%@=%d", sel, [[UIApplication sharedApplication] respondsToSelector:NSSelectorFromString(sel)]]];
    NSString *head = missing.count == 0 ? @"all private entry points present" : [@"MISSING: " stringByAppendingString:[missing componentsJoinedByString:@", "]];
    return [NSString stringWithFormat:@"%@; routing: %@", head, [routing componentsJoinedByString:@" "]];
}

- (instancetype)initWithWindow:(UIWindow *)window {
    if ((self = [super init])) {
        _window = window;
        _active = [NSMutableArray array];
        _nextIndex = 1;
    }
    return self;
}

- (NSUInteger)activeCount { return _active.count; }

- (NSArray<NSValue *> *)activePoints {
    NSMutableArray *out = [NSMutableArray array];
    for (RigTouch *p in _active) [out addObject:[NSValue valueWithCGPoint:p.point]];
    return out;
}

- (IOHIDEventRef)hidEventFor:(NSArray<RigTouch *> *)touches {
    uint64_t now = mach_absolute_time();
    IOHIDEventRef hand = createHand(kCFAllocatorDefault, now, kTransducerHand, 0, 0, kEventTouch, 0,
                                    0, 0, 0, 0, 0, 0, 1, 0);
    setInt(hand, kFieldIsDisplayIntegrated, 1);
    if (setSender) setSender(hand, 0x000000010000027FULL);
    for (RigTouch *p in touches) {
        UITouchPhase phase = p.touch.phase;
        uint32_t mask = phase == UITouchPhaseMoved ? kEventPosition : (kEventRange | kEventTouch);
        if (self.viaEnqueue && phase == UITouchPhaseStationary) mask = 0;   // a real stream: no change
        boolean_t touching = (phase == UITouchPhaseEnded || phase == UITouchPhaseCancelled) ? 0 : 1;
        CGSize screen = UIScreen.mainScreen.bounds.size;
        IOHIDFloat x = self.normalized ? p.point.x / screen.width : p.point.x;
        IOHIDFloat y = self.normalized ? p.point.y / screen.height : p.point.y;
        IOHIDEventRef finger = createFinger(kCFAllocatorDefault, now, p.pathIndex, p.pathIndex + 1, mask,
                                            x, y, 0, 0, 0, 5, 5, 1, 1, 1,
                                            touching, touching, 0);
        setInt(finger, kFieldIsDisplayIntegrated, 1);
        appendEvent(hand, finger, 0);
        CFRelease(finger);
    }
    return hand;
}

- (void)dispatch {
    if (self.viaEnqueue) {
        IOHIDEventRef hid = [self hidEventFor:_active];
        [[UIApplication sharedApplication] _enqueueHIDEvent:hid];
        CFRelease(hid);
        return;
    }
    NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    for (RigTouch *p in _active) [p.touch setTimestamp:now];
    UIApplication *app = [UIApplication sharedApplication];
    UIEvent *event = [app _touchesEvent];
    [event _clearTouches];
    IOHIDEventRef hid = [self hidEventFor:_active];
    [event _setHIDEvent:hid];
    for (RigTouch *p in _active) [event _addTouch:p.touch forDelayedDelivery:NO];
    [app sendEvent:event];
    CFRelease(hid);
}

- (void)beginAt:(NSArray<NSValue *> *)points {
    if (_active.count == 0) _nextIndex = 1;   // a new gesture: path indexes from 1, as a real hand's
    for (RigTouch *p in _active) [p.touch setPhase:UITouchPhaseStationary];
    for (NSValue *v in points) {
        CGPoint pt = v.CGPointValue;
        UITouch *t = [UITouch new];
        [t setWindow:_window];
        [t setTapCount:1];
        [t _setLocationInWindow:pt resetPrevious:YES];
        UIView *hit = [_window hitTest:pt withEvent:nil];
        [t setView:hit];
        [t setPhase:UITouchPhaseBegan];
        // Only the first finger of a gesture is the first touch for the view (a real hand's later
        // fingers are not); TOUCHRIG_FIRSTFLAG=all flags every touch, as KIF does for one-finger taps.
        BOOL flagAll = [[[NSProcessInfo processInfo].environment objectForKey:@"TOUCHRIG_FIRSTFLAG"] isEqualToString:@"all"];
        [t _setIsFirstTouchForView:(flagAll || _active.count == 0)];
        if ([t respondsToSelector:@selector(setIsTap:)]) [t setIsTap:NO];
        if ([t respondsToSelector:@selector(setGestureView:)]) [t setGestureView:hit];
        RigTouch *p = [RigTouch new];
        p.touch = t; p.point = pt; p.pathIndex = _nextIndex++;
        if ([t respondsToSelector:@selector(_setPathIndex:)]) [t _setPathIndex:(unsigned char)p.pathIndex];
        if ([t respondsToSelector:@selector(_setPathIdentity:)]) [t _setPathIdentity:2];
        IOHIDEventRef own = [self hidEventFor:@[p]];
        [t _setHidEvent:own];
        CFRelease(own);
        [_active addObject:p];
    }
    [self dispatch];
}

- (void)moveTo:(NSArray<NSValue *> *)points {
    NSAssert(points.count == _active.count, @"moveTo needs one point per active touch");
    [_active enumerateObjectsUsingBlock:^(RigTouch *p, NSUInteger i, BOOL *stop) {
        CGPoint pt = points[i].CGPointValue;
        if (CGPointEqualToPoint(pt, p.point)) {
            [p.touch setPhase:UITouchPhaseStationary];
        } else {
            p.point = pt;
            [p.touch _setLocationInWindow:pt resetPrevious:NO];
            [p.touch setPhase:UITouchPhaseMoved];
        }
    }];
    [self dispatch];
}

- (void)endIndices:(NSIndexSet *)indices {
    [_active enumerateObjectsUsingBlock:^(RigTouch *p, NSUInteger i, BOOL *stop) {
        [p.touch setPhase:[indices containsIndex:i] ? UITouchPhaseEnded : UITouchPhaseStationary];
    }];
    [self dispatch];
    [_active removeObjectsAtIndexes:indices];
}

- (void)cancelAll {
    for (RigTouch *p in _active) [p.touch setPhase:UITouchPhaseCancelled];
    [self dispatch];
    [_active removeAllObjects];
}

@end
