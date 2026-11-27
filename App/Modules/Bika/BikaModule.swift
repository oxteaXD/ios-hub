import SwiftUI

/// 新写的哔咔界面的接入层。
///
/// 上游的 Pica（Objective-C 加 QMUI）在新系统上适配得不好，这一套是照着它的接口用 SwiftUI 重写的：
/// 接口的地址、请求头、签名照搬上游（`BikaAPI`），界面是自己的，和另外两个应用一个风格。
/// 源码直接编在宿主里，不依赖上游的任何代码和界面库。
///
/// 上游那一套暂时还留着（`PicaModule`，启动页上的另一本书），等这一套确认好用了再去掉。
/// 两边共用同一个登录状态。
enum BikaModule {
    static let id = "bika"

    /// 哔咔的粉色，取自上游的主题色 `PCColorHotPink`（255, 105, 180）。
    static let accent = Color(red: 1.0, green: 105.0 / 255.0, blue: 180.0 / 255.0)

    static let descriptor = HubModule(
        id: id,
        title: "哔咔",
        subtitle: "新写的界面，试用中",
        systemImage: "books.vertical.fill",
        // 比强调色深一些：封面上印的是白字。
        cardColor: Color(red: 0.84, green: 0.27, blue: 0.50),
        accent: accent,
        // 用的都是系统的颜色，深浅色跟着系统走。
        interfaceStyle: nil,
        // 漫画是竖着看的，和另外两个应用一样在 iPhone 上只开竖屏。
        portraitOnlyOnPhone: true,
        urlSchemes: [],
        start: {},
        makeRootView: {
            AnyView(BikaRootView())
        },
        scenePhaseDidChange: nil
    )
}
