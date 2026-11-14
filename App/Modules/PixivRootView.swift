import Kingfisher
import SwiftData
import SwiftUI
import UIKit

/// Pixiv-SwiftUI 的入口视图。
///
/// 内容照搬上游 `App/PixivApp.swift` 里 `WindowGroup` 的那一段（iOS 部分）。上游把它写在 `Scene`
/// 里，没法直接嵌进别的视图，所以在这里重写一份。上游的 `ContentView` 等仍然直接使用，没有复制。
///
/// 上游改了入口文件时，`scripts/prepare.py` 会给出提醒，届时对照着更新这里。与上游的差别只有两处：
/// 1. 初始化只在还没完成时执行。宿主切换模块会重新创建这个视图，不需要每次都重跑一遍。
/// 2. 没有接入 `AppCommands`（iPad 外接键盘的菜单命令），它只能挂在 `Scene` 上。
struct PixivRootView: View {
    @State private var initializer = AppInitializer.shared
    @State private var pendingUpdateInfo: AppUpdateInfo?

    var body: some View {
        ZStack {
            if let initializationError = initializer.initializationError {
                ContentUnavailableView {
                    Label("无法打开本地数据", systemImage: "externaldrive.badge.xmark")
                } description: {
                    Text(initializationError.localizedDescription)
                }
            } else if initializer.isLaunching || initializer.accountStore == nil {
                LaunchScreenView()
            } else {
                ContentView()
                    .environment(initializer.accountStore ?? AccountStore.shared)
                    .environment(initializer.illustStore ?? IllustStore.shared)
                    .environment(initializer.userSettingStore ?? UserSettingStore.shared)
                    .environment(ThemeManager.shared)
                    .environment(BookmarkActionService.shared)
                    .modelContainer(initializer.modelContainer ?? DataContainer.shared.modelContainer)
            }
        }
        .withGlobalToast()
        .sheet(item: $pendingUpdateInfo) { info in
            UpdateAvailableSheet(
                updateInfo: info,
                isPresented: Binding(
                    get: { pendingUpdateInfo != nil },
                    set: { if !$0 { pendingUpdateInfo = nil } }
                ),
                onSkip: {
                    UpdateChecker.shared.skipVersion(info.version)
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ShowUpdateNotification"))) { notification in
            if let info = notification.object as? AppUpdateInfo {
                pendingUpdateInfo = info
            }
        }
        .task {
            if initializer.isLaunching || initializer.accountStore == nil {
                await initializer.performInitialization()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            handleMemoryWarning()
        }
    }

    /// 收到内存警告时清理 Kingfisher 等内存缓存（与上游一致）。
    private func handleMemoryWarning() {
        ImageCache.default.clearMemoryCache()
        BookmarkCacheService.shared.getCache()?.clearMemoryCache()
        IllustStore.shared.clearMemoryCache()
        NovelStore.shared.clearMemoryCache()
        SearchStore.shared.clearMemoryCache()
    }
}
