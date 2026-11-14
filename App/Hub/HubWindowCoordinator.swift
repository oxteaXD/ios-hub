import SwiftUI
import UIKit

/// 切换模块时对窗口做的统一处理。
enum HubWindowCoordinator {
    private static var windows: [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
    }

    static func currentInterfaceStyle() -> UIUserInterfaceStyle {
        let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first
        return window?.overrideUserInterfaceStyle ?? .unspecified
    }

    static func apply(interfaceStyle: UIUserInterfaceStyle, tint: Color?) {
        for window in windows {
            window.overrideUserInterfaceStyle = interfaceStyle
        }
        apply(tint: tint)
    }

    /// tint 为 nil 时恢复成全局强调色。
    static func apply(tint: Color?) {
        let color = tint.map { UIColor($0) }
        for window in windows {
            window.tintColor = color
        }
    }

    /// 让系统重新询问应用代理当前允许的屏幕方向；如果当前方向不再被允许，系统会自动转回去。
    static func refreshSupportedOrientations() {
        for window in windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    static func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
