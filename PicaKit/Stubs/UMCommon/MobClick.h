//
//  MobClick.h
//  PicaKit
//
//  友盟统计的空实现。
//
//  上游接了友盟的统计和性能监控（UMCommon、UMDevice、UMAPM，都是只有二进制的 SDK）。合并进宿主之后，
//  这些 SDK 会和别的应用待在同一个进程里，性能监控会连别的应用的网络请求一起采集，登录时还会上报账号，
//  所以没有带进来。上游代码里调用统计的地方保持原样，由这里提供同名的类，所有方法什么都不做。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MobClick : NSObject

+ (void)setAutoPageEnabled:(BOOL)value;

+ (void)event:(NSString *)eventId;
+ (void)event:(NSString *)eventId label:(nullable NSString *)label;
+ (void)event:(NSString *)eventId attributes:(nullable NSDictionary *)attributes;
+ (void)event:(NSString *)eventId attributes:(nullable NSDictionary *)attributes counter:(int)number;

+ (void)beginLogPageView:(NSString *)pageName;
+ (void)endLogPageView:(NSString *)pageName;

+ (void)profileSignInWithPUID:(NSString *)puid;
+ (void)profileSignInWithPUID:(NSString *)puid provider:(nullable NSString *)provider;
+ (void)profileSignOff;

@end

NS_ASSUME_NONNULL_END
