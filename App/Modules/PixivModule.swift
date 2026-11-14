import SwiftUI

/// Pixiv-SwiftUI 的接入层。
///
/// 它的源码直接编译进宿主的 App target（它的图片、文案、标签数据都从主 bundle 里找），
/// 所以这里不需要导入任何模块，入口视图见 `PixivRootView`。
enum PixivModule {
    static let id = "pixiv"

    static let descriptor = HubModule(
        id: id,
        title: "Pixiv",
        subtitle: "Pixiv 第三方客户端",
        systemImage: "paintpalette.fill",
        cardColor: Color(red: 0.0, green: 0.588, blue: 0.98),
        // 它的强调色由自己的主题设置管理，宿主不干预。
        accent: nil,
        // 上游工程在 iPhone 上只开放竖屏。
        portraitOnlyOnPhone: true,
        urlSchemes: [],
        // 它的初始化在入口视图出现时进行，见 `PixivRootView`。
        start: {},
        makeRootView: {
            AnyView(PixivRootView())
        },
        scenePhaseDidChange: nil
    )
}
