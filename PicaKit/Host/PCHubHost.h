//
//  PCHubHost.h
//  PicaKit
//
//  Pica 在宿主（Hub）里的入口。
//
//  上游的 AppDelegate 自己建窗口，并通过更换窗口的根控制器在「登录页」和「主界面」之间切换。
//  合并进宿主之后窗口是宿主的，所以由这个类接手上游 AppDelegate 做的那几件事：
//  按登录状态决定显示哪个界面、提供切换的入口。界面放在一个容器控制器里，宿主把容器嵌进自己的界面。
//
//  上游代码里原本找 AppDelegate 的地方，都由 patches/pica/hub-host.patch 改成了找这个类。
//

#import <UIKit/UIKit.h>

@class PCTabBarViewController;

NS_ASSUME_NONNULL_BEGIN

/// 承载 Pica 全部界面的容器。同一时间只显示一个子控制器（登录页或主界面）。
@interface PCHubRootViewController : UIViewController

@property (nonatomic, strong, readonly, nullable) UIViewController *contentViewController;

- (void)showContentViewController:(UIViewController *)contentViewController animated:(BOOL)animated;

@end

@interface PCHubHost : NSObject

@property (class, nonatomic, strong, readonly) PCHubHost *sharedHost;

/// 宿主嵌进自己界面里的容器。第一次取用时完成 Pica 的启动（相当于上游的 didFinishLaunching）。
@property (nonatomic, strong, readonly) PCHubRootViewController *rootViewController;

/// 当前显示的主界面；显示登录页时为 nil。
@property (nonatomic, strong, readonly, nullable) PCTabBarViewController *currentTabBarController;

/// 给宿主的界面测试看的自检信息，不参与任何逻辑。
@property (nonatomic, copy, readonly) NSString *diagnostics;

/// 回到登录页（退出登录、登录状态失效时）。对应上游 AppDelegate 的同名方法。
- (void)setRootViewControllerToLogin;

/// 进入主界面（登录成功后）。对应上游 AppDelegate 的同名方法。
- (void)setRootViewControllerToTab;

@end

NS_ASSUME_NONNULL_END
