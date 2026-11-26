//
//  UMCommon.h
//  PicaKit
//
//  友盟统计的空实现，说明见同目录的 MobClick.h。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UMConfigure : NSObject

+ (void)initWithAppkey:(NSString *)appKey channel:(nullable NSString *)channel;
+ (void)setLogEnabled:(BOOL)enabled;
+ (void)setEncryptEnabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
