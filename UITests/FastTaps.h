#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

/// Plays a whole run of taps in one go at human speed. XCUICoordinate.tap
/// waits for the app to go idle after every tap (~0.5 s each), far slower
/// than anyone types, and keyboards behave differently at that pace.
/// Uses XCTest's private event synthesis (the same one WebDriverAgent uses).
@interface FastTaps : NSObject
/// `points` are NSValue CGPoints in screen points; `times` the start of each
/// tap in seconds from now. Each touch lasts `hold` seconds. Blocks until done.
+ (BOOL)tapPoints:(NSArray<NSValue *> *)points atTimes:(NSArray<NSNumber *> *)times hold:(double)hold error:(NSError **)error;
@end
