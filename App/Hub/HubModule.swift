import SwiftUI
import UIKit

/// 宿主里的一个子应用。
///
/// 新增子应用时，构造一个 `HubModule` 并登记到 `HubModuleRegistry.all` 即可，宿主的其余部分不需要改。
struct HubModule: Identifiable {
    /// 稳定的标识，会写进偏好设置，定下来之后不要改。
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    /// 启动页上卡片图标的底色。
    let cardColor: Color
    /// 模块自己的强调色；为 nil 时沿用全局强调色。
    let accent: Color?
    /// 模块固定使用的深浅色。只有浅色（或只有深色）界面、自己又不管理窗口外观的模块填这一项，
    /// 宿主在它显示期间把整个场景固定成这个外观；为 nil 时由模块自己管理，宿主只负责切换时保存和恢复。
    let interfaceStyle: UIUserInterfaceStyle?
    /// 在 iPhone 上是否只允许竖屏，与模块上游工程的设置保持一致。
    let portraitOnlyOnPhone: Bool
    /// 属于这个模块的 URL scheme（小写）。收到这类链接时宿主会先切到该模块。
    let urlSchemes: [String]
    /// 首次进入模块前调用一次，用来做模块自己的启动初始化。
    let start: () -> Void
    let makeRootView: () -> AnyView
    /// 模块已启动但界面没有挂载时，宿主把场景阶段变化转发给它；不需要的模块传 nil。
    let scenePhaseDidChange: ((ScenePhase) -> Void)?
}

enum HubModuleRegistry {
    /// 启动页按这个顺序排列。
    static let all: [HubModule] = [
        EhPandaModule.descriptor,
        PixivModule.descriptor,
        PicaModule.descriptor,
    ]
}
