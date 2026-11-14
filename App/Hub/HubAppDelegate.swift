import UIKit

/// 宿主的应用代理。只处理必须由应用代理接收的系统回调，再转交给对应的模块。
final class HubAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 在这里把宿主状态建好：开启了「启动时直接进入上次使用的应用」时，那个应用的启动初始化
        // 就发生在这一刻，和它单独运行时的时机一致，而不是推迟到系统第一次来问屏幕方向的时候。
        _ = HubState.shared
        return true
    }

    /// 系统为后台下载会话唤醒 App 时走这里。目前只有 EhPanda 使用后台会话。
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        EhPandaModule.handleBackgroundSessionEvents(
            application,
            identifier: identifier,
            completionHandler: completionHandler
        )
    }

    /// 各模块对屏幕方向的要求不同，由当前显示的模块决定。
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        HubState.shared.supportedOrientations
    }
}
