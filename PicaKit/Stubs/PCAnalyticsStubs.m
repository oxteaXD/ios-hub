//
//  PCAnalyticsStubs.m
//  PicaKit
//
//  友盟统计的空实现，说明见 UMCommon/MobClick.h。
//

#import <UMCommon/MobClick.h>
#import <UMCommon/UMCommon.h>

@implementation MobClick

+ (void)setAutoPageEnabled:(BOOL)value {}

+ (void)event:(NSString *)eventId {}
+ (void)event:(NSString *)eventId label:(NSString *)label {}
+ (void)event:(NSString *)eventId attributes:(NSDictionary *)attributes {}
+ (void)event:(NSString *)eventId attributes:(NSDictionary *)attributes counter:(int)number {}

+ (void)beginLogPageView:(NSString *)pageName {}
+ (void)endLogPageView:(NSString *)pageName {}

+ (void)profileSignInWithPUID:(NSString *)puid {}
+ (void)profileSignInWithPUID:(NSString *)puid provider:(NSString *)provider {}
+ (void)profileSignOff {}

@end

@implementation UMConfigure

+ (void)initWithAppkey:(NSString *)appKey channel:(NSString *)channel {}
+ (void)setLogEnabled:(BOOL)enabled {}
+ (void)setEncryptEnabled:(BOOL)enabled {}

@end
