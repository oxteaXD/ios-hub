import AppFeature
import SwiftUI
import UIKit

/// EhPanda 的接入层。
///
/// EhPanda 上游是「薄壳 App + 本地 Swift 包」的结构，壳里只有一个应用代理和一个根视图。
/// 这里做的就是壳原本做的事：持有它的应用代理（里面是整个 App 的状态仓库），并把根视图交给宿主。
enum EhPandaModule {
    static let id = "ehpanda"

    /// EhPanda 的应用代理，首次用到时才创建：在那之前它不会改动任何全局设置，也不会发起网络请求。
    private static var appDelegate: AppFeature.AppDelegate?

    @discardableResult
    static func startIfNeeded() -> AppFeature.AppDelegate {
        if let existing = appDelegate {
            return existing
        }
        let delegate = AppFeature.AppDelegate()
        appDelegate = delegate
        _ = delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
        return delegate
    }

    /// 系统为后台下载会话唤醒 App 时调用。这时 EhPanda 可能还没启动过，需要先把它拉起来。
    static func handleBackgroundSessionEvents(
        _ application: UIApplication,
        identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        let delegate = startIfNeeded()
        HubState.shared.noteModuleStarted(id)
        delegate.application(
            application,
            handleEventsForBackgroundURLSession: identifier,
            completionHandler: completionHandler
        )
    }

    static let descriptor = HubModule(
        id: id,
        title: "EhPanda",
        subtitle: "E-Hentai 客户端",
        systemImage: "books.vertical.fill",
        cardColor: Color("EhPandaAccent"),
        // 上游用的是壳工程资源目录里的全局强调色，这里改成只对它自己的界面生效。
        accent: Color("EhPandaAccent"),
        portraitOnlyOnPhone: false,
        urlSchemes: ["ehpanda"],
        start: {
            _ = startIfNeeded()
        },
        makeRootView: {
            AnyView(AppFeature.RootView(appDelegate: startIfNeeded()))
        },
        scenePhaseDidChange: { phase in
            if let delegate = appDelegate {
                delegate.hubForward(scenePhase: phase)
            }
        }
    )
}
