//
//  PCHubHost.m
//  PicaKit
//

#import "PCHubHost.h"

#import <objc/runtime.h>

#import "PCVendorHeader.h"
#import "PCLocalKeyHeader.h"
#import "PCThemeManager.h"
#import "PCLoginController.h"
#import "PCTabBarViewController.h"

#pragma mark - 容器

@interface PCHubRootViewController ()

@property (nonatomic, strong, readwrite, nullable) UIViewController *contentViewController;

@end

@implementation PCHubRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
}

- (void)showContentViewController:(UIViewController *)contentViewController animated:(BOOL)animated {
    if (contentViewController == self.contentViewController) {
        return;
    }
    [self loadViewIfNeeded];

    void (^swap)(void) = ^{
        UIViewController *previous = self.contentViewController;
        if (previous) {
            [previous willMoveToParentViewController:nil];
            [previous.view removeFromSuperview];
            [previous removeFromParentViewController];
        }

        self.contentViewController = contentViewController;
        [self addChildViewController:contentViewController];
        contentViewController.view.frame = self.view.bounds;
        contentViewController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:contentViewController.view];
        [contentViewController didMoveToParentViewController:self];
    };

    if (animated && self.view.window) {
        [UIView transitionWithView:self.view
                          duration:0.35
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:swap
                        completion:nil];
    } else {
        swap();
    }
    [self setNeedsStatusBarAppearanceUpdate];
}

- (UIViewController *)childViewControllerForStatusBarStyle {
    return self.contentViewController;
}

- (UIViewController *)childViewControllerForStatusBarHidden {
    return self.contentViewController;
}

- (UIViewController *)childViewControllerForHomeIndicatorAutoHidden {
    return self.contentViewController;
}

- (UIViewController *)childViewControllerForScreenEdgesDeferringSystemGestures {
    return self.contentViewController;
}

@end

#pragma mark - 入口

@interface PCHubHost ()

@property (nonatomic, strong, readwrite) PCHubRootViewController *rootViewController;
@property (nonatomic, strong, nullable) PCLoginController *loginController;
@property (nonatomic, strong, nullable) PCTabBarViewController *tabBarController;
@property (nonatomic, assign) BOOL started;
/// 有没有给应用代理补上 window 方法，见 -ensureDelegateWindow。
@property (nonatomic, assign) BOOL injectedDelegateWindow;
/// 取自检信息时在主窗口上见到过的最近一条提示，见 -noteVisibleTip。
@property (nonatomic, copy, nullable) NSString *lastSeenTipText;

@end

@implementation PCHubHost

+ (PCHubHost *)sharedHost {
    static PCHubHost *host = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        host = [[PCHubHost alloc] init];
    });
    return host;
}

- (PCHubRootViewController *)rootViewController {
    if (!_rootViewController) {
        _rootViewController = [[PCHubRootViewController alloc] init];
    }
    [self startIfNeeded];
    return _rootViewController;
}

- (PCTabBarViewController *)currentTabBarController {
    return _rootViewController.contentViewController == _tabBarController ? _tabBarController : nil;
}

#pragma mark 启动

/// 对应上游 AppDelegate 的 application:didFinishLaunchingWithOptions:。
/// 友盟统计没有带进来（见 Stubs/UMCommon），所以这里没有上游的 configUMeng。
- (void)startIfNeeded {
    if (self.started) {
        return;
    }
    self.started = YES;

    [self ensureDelegateWindow];
    [SDImageCodersManager.sharedManager addCoder:SDImageVideoCoder.sharedCoder];

    // 开关打开时的颜色。上游是通过 QMUI 的配置表设到全局的（会连别的应用的开关一起改），
    // 配置表里那一项已经去掉，这里改为只对 Pica 自己的界面生效。
    [UISwitch appearanceWhenContainedInInstancesOfClasses:@[QMUINavigationController.class]].onTintColor = UIColor.pc_tintColor;

    NSString *token = [kPCUserDefaults stringForKey:PC_AUTHORIZATION_TOKEN];
    if (token) {
        SDWebImageDownloader *downloader = [SDWebImageManager sharedManager].imageLoader;
        [downloader setValue:token forHTTPHeaderField:@"authorization"];
        [_rootViewController showContentViewController:self.tabBarController animated:NO];
    } else {
        [_rootViewController showContentViewController:self.loginController animated:NO];
    }
}

- (void)setRootViewControllerToLogin {
    PCHubRootViewController *root = self.rootViewController;
    if (root.contentViewController != self.loginController) {
        [root showContentViewController:self.loginController animated:YES];
        self.tabBarController = nil;
    }
}

- (void)setRootViewControllerToTab {
    PCHubRootViewController *root = self.rootViewController;
    if (root.contentViewController != self.tabBarController) {
        [root showContentViewController:self.tabBarController animated:NO];
        self.loginController = nil;
    }
}

- (PCLoginController *)loginController {
    if (!_loginController) {
        _loginController = [[PCLoginController alloc] init];
    }
    return _loginController;
}

- (PCTabBarViewController *)tabBarController {
    if (!_tabBarController) {
        _tabBarController = [[PCTabBarViewController alloc] init];
    }
    return _tabBarController;
}

#pragma mark 右滑返回

+ (void)guardBackSwipeOnScrollView:(UIScrollView *)scrollView {
    Class guardClass = NSClassFromString(@"HubEdgeBackGuard");
    SEL installSelector = NSSelectorFromString(@"installOnScrollView:");
    if (!scrollView || ![guardClass respondsToSelector:installSelector]) {
        return;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [guardClass performSelector:installSelector withObject:scrollView];
#pragma clang diagnostic pop
}

#pragma mark 主窗口

/// 宿主的主窗口：应用场景里的关键窗口，没有就取第一个。
+ (nullable UIWindow *)hubMainWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            ![scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        UIWindow *window = windowScene.keyWindow ?: windowScene.windows.firstObject;
        if (window) {
            return window;
        }
    }
    return nil;
}

/// QMUI 的提示、弹窗等都要先找到「主窗口」（UIApplication 的 qmui_delegateWindow）：它先问场景代理的 window，
/// 问不到再问应用代理的 window。宿主是 SwiftUI 的生命周期，这两个代理都是系统提供的，不保证有 window。
/// 所以应用代理没有这个方法时给它补一个，返回宿主的主窗口；场景代理那条路走得通时，补的这个不会被用到。
- (void)ensureDelegateWindow {
    id<UIApplicationDelegate> delegate = UIApplication.sharedApplication.delegate;
    if (!delegate || [delegate respondsToSelector:@selector(window)]) {
        return;
    }
    IMP implementation = imp_implementationWithBlock(^UIWindow *(__unused id delegateObject) {
        return [PCHubHost hubMainWindow];
    });
    self.injectedDelegateWindow = class_addMethod(object_getClass(delegate), @selector(window), implementation, "@@:");
}

/// Pica 的提示（QMUITips）是加在主窗口上的，只显示一两秒，界面测试来不及直接看到它。
/// 所以宿主每隔一小会儿取一次自检信息，取的时候顺便看一眼主窗口，把正在显示的提示文字记下来。
- (void)noteVisibleTip {
    UIWindow *window = UIApplication.sharedApplication.qmui_delegateWindow ?: [PCHubHost hubMainWindow];
    for (UIView *subview in window.subviews) {
        if (![subview isKindOfClass:QMUIToastView.class]) {
            continue;
        }
        UIView *contentView = ((QMUIToastView *)subview).contentView;
        if (![contentView isKindOfClass:QMUIToastContentView.class]) {
            continue;
        }
        QMUIToastContentView *content = (QMUIToastContentView *)contentView;
        NSString *text = content.textLabelText.length ? content.textLabelText : content.detailTextLabelText;
        if (text.length) {
            self.lastSeenTipText = text;
        }
    }
}

- (NSString *)diagnostics {
    [self noteVisibleTip];
    BOOL sceneDelegateHasWindow = NO;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene.delegate respondsToSelector:@selector(window)] &&
            [scene.delegate performSelector:@selector(window)] != nil) {
            sceneDelegateHasWindow = YES;
        }
    }
    UIWindow *delegateWindow = UIApplication.sharedApplication.qmui_delegateWindow;
    NSString *source = @"没有找到";
    if (delegateWindow) {
        source = sceneDelegateHasWindow ? @"场景代理" : @"应用代理（宿主补的）";
    }
    NSString *content = @"无";
    if (_rootViewController.contentViewController == _loginController && _loginController) {
        content = @"登录页";
    } else if (_rootViewController.contentViewController == _tabBarController && _tabBarController) {
        content = @"主界面";
    }
    return [NSString stringWithFormat:@"QMUI 主窗口来自：%@；补过应用代理：%@；当前界面：%@；见到过的最近一条提示：%@",
            source, self.injectedDelegateWindow ? @"是" : @"否", content, self.lastSeenTipText ?: @"无"];
}

@end
