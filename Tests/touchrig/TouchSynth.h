#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/// TEST ONLY (Tests/touchrig, never in the app): synthesizes multi-finger direct touches in-process,
/// the way KIF does, so the real recognizers can be driven with three and four fingers in the
/// simulator.
@interface TouchSynth : NSObject
+ (NSString *)selfCheck;
- (instancetype)initWithWindow:(UIWindow *)window;
/// New touches at these window points (phase began); the others stationary. One event.
- (void)beginAt:(NSArray<NSValue *> *)points;
/// Every active touch to these window points, in the order they began. One event.
- (void)moveTo:(NSArray<NSValue *> *)points;
/// These active touches end (indices into the active list); the others stationary. One event.
- (void)endIndices:(NSIndexSet *)indices;
/// Every active touch cancelled. One event.
- (void)cancelAll;
@property (nonatomic, readonly) NSUInteger activeCount;
/// The real routing path instead: a digitizer hand event handed to UIKit's own HID entry point, so
/// UIKit makes the touches, hit-tests every window and runs every recognizer (the editing overlay's
/// too). Points are screen points; `normalized` sends them as fractions of the screen.
@property (nonatomic) BOOL viaEnqueue;
@property (nonatomic) BOOL normalized;
- (NSArray<NSValue *> *)activePoints;
@end
NS_ASSUME_NONNULL_END
