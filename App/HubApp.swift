import SwiftUI
import UIKit

/// 整个 App 唯一的程序入口。各个子应用原本的 `@main` 都已去掉，改由 `HubRootView` 按需挂载。
@main
struct HubApp: App {
    @UIApplicationDelegateAdaptor(HubAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            HubRootView()
        }
    }
}
