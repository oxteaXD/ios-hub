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
        cardColor: PixivPalette.brand,
        // 强调色固定为 Pixiv 官方的品牌蓝（上游的主题色预设已经去掉）。
        // 上游在各个标签页的内容上用 `.tint(nil)` 回到全局强调色，所以全局强调色也设成了同一个蓝，
        // 见 project.yml 里的 ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME。
        accent: PixivPalette.brand,
        // 深浅色由它自己的「外观」设置管理。
        interfaceStyle: nil,
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
