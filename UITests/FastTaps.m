#import "FastTaps.h"
#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>

@interface XCPointerEventPath : NSObject
- (instancetype)initForTouchAtPoint:(CGPoint)point offset:(double)offset;
- (void)liftUpAtOffset:(double)offset;
@end

@interface XCSynthesizedEventRecord : NSObject
- (instancetype)initWithName:(NSString *)name interfaceOrientation:(UIInterfaceOrientation)orientation;
- (void)addPointerEventPath:(XCPointerEventPath *)path;
@end

@protocol BKEventSynthesizer <NSObject>
- (void)synthesizeEvent:(XCSynthesizedEventRecord *)event completion:(void (^)(BOOL, NSError *))completion;
@end

@implementation FastTaps
+ (BOOL)tapPoints:(NSArray<NSValue *> *)points atTimes:(NSArray<NSNumber *> *)times hold:(double)hold error:(NSError **)error {
    Class recordClass = NSClassFromString(@"XCSynthesizedEventRecord");
    Class pathClass = NSClassFromString(@"XCPointerEventPath");
    id device = [XCUIDevice sharedDevice];
    if (!recordClass || !pathClass || ![device respondsToSelector:NSSelectorFromString(@"eventSynthesizer")]) {
        if (error) *error = [NSError errorWithDomain:@"FastTaps" code:1 userInfo:@{NSLocalizedDescriptionKey: @"event synthesis API not found"}];
        return NO;
    }
    XCSynthesizedEventRecord *record = [[recordClass alloc] initWithName:@"bench" interfaceOrientation:UIInterfaceOrientationPortrait];
    for (NSUInteger i = 0; i < points.count; i++) {
        double t = times[i].doubleValue;
        XCPointerEventPath *path = [[pathClass alloc] initForTouchAtPoint:points[i].CGPointValue offset:t];
        [path liftUpAtOffset:t + hold];
        [record addPointerEventPath:path];
    }
    id<BKEventSynthesizer> synth = [device performSelector:NSSelectorFromString(@"eventSynthesizer")];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block BOOL ok = NO; __block NSError *err = nil;
    [synth synthesizeEvent:record completion:^(BOOL result, NSError *e) { ok = result; err = e; dispatch_semaphore_signal(done); }];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(120 * NSEC_PER_SEC)));
    if (error) *error = err;
    return ok;
}
@end
