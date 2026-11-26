import Observation
import SwiftUI
import UIKit

/// 宿主的全局状态：有哪些模块、当前显示哪一个，以及切换模块时要做的收尾工作。
///
/// 同一时间只挂载一个模块的界面。各模块自己的数据层（EhPanda 的 store、Pixiv 的各个单例）在
/// 界面卸载后依然存在，所以切回来时登录状态、下载队列等都还在。
@Observable
final class HubState {
    static let shared = HubState()

    private enum Keys {
        static let lastModule = "hub.lastModule"
        static let autoEnterLastModule = "hub.autoEnterLastModule"
    }

    /// 记录窗口外观时，启动页自己用的键。
    private static let launcherStyleKey = "hub.launcher"

    let modules: [HubModule]
    private(set) var activeModuleID: String? = nil

    var autoEnterLastModule: Bool {
        didSet { UserDefaults.standard.set(autoEnterLastModule, forKey: Keys.autoEnterLastModule) }
    }

    @ObservationIgnored private var startedModuleIDs: Set<String> = []
    /// 各模块（以及启动页）离开时窗口上的深浅色设置，回来时原样恢复。
    @ObservationIgnored private var windowStyles: [String: UIUserInterfaceStyle] = [:]

    private init() {
        modules = HubModuleRegistry.all
        autoEnterLastModule = UserDefaults.standard.bool(forKey: Keys.autoEnterLastModule)
        if autoEnterLastModule,
           let lastID = UserDefaults.standard.string(forKey: Keys.lastModule),
           let module = modules.first(where: { $0.id == lastID }) {
            start(module)
            activeModuleID = module.id
        }
    }

    var activeModule: HubModule? {
        guard let activeModuleID else { return nil }
        return modules.first(where: { $0.id == activeModuleID })
    }

    // MARK: 切换

    func activate(_ module: HubModule) {
        switchTo(module)
    }

    func goHome() {
        switchTo(nil)
    }

    private func switchTo(_ target: HubModule?) {
        guard target?.id != activeModuleID else { return }

        HubWindowCoordinator.dismissKeyboard()

        // 两个子应用都会直接改窗口的深浅色设置。离开时记下来、进入时恢复，彼此才不会串。
        windowStyles[styleKey(for: activeModuleID)] = HubWindowCoordinator.currentInterfaceStyle()
        // 先换成目标模块上次留下的外观再启动它：模块启动时自己套用的外观才不会被旧值盖掉。
        // 固定了深浅色的模块（比如只有浅色界面的 Pica）不看上次留下的值，每次都用它固定的那个。
        HubWindowCoordinator.apply(
            interfaceStyle: target?.interfaceStyle ?? windowStyles[styleKey(for: target?.id)] ?? .unspecified,
            fixedForScene: target?.interfaceStyle,
            tint: target?.accent
        )

        if let target {
            start(target)
            UserDefaults.standard.set(target.id, forKey: Keys.lastModule)
        }
        activeModuleID = target?.id
        HubWindowCoordinator.refreshSupportedOrientations()
    }

    private func start(_ module: HubModule) {
        guard !startedModuleIDs.contains(module.id) else { return }
        startedModuleIDs.insert(module.id)
        module.start()
    }

    /// 模块不是经由 `activate` 启动的时候（例如系统为后台下载唤醒 App）调用，让宿主知道它已经在运行。
    func noteModuleStarted(_ id: String) {
        startedModuleIDs.insert(id)
    }

    private func styleKey(for moduleID: String?) -> String {
        moduleID ?? Self.launcherStyleKey
    }

    // MARK: 系统事件

    /// 窗口出现后调用一次：启动时直接进入模块的情况下，那时窗口还不存在，强调色、固定的深浅色和方向要补设。
    func syncWindowAppearance() {
        if let style = activeModule?.interfaceStyle {
            HubWindowCoordinator.apply(interfaceStyle: style, fixedForScene: style, tint: activeModule?.accent)
        } else {
            HubWindowCoordinator.apply(tint: activeModule?.accent)
        }
        HubWindowCoordinator.refreshSupportedOrientations()
    }

    /// 已启动但界面没挂载的模块收不到场景阶段变化，由宿主代为转发。
    func forward(scenePhase: ScenePhase) {
        for module in modules where module.id != activeModuleID && startedModuleIDs.contains(module.id) {
            module.scenePhaseDidChange?(scenePhase)
        }
    }

    /// 收到某个模块的链接而它的界面没挂载时，先切过去，再把链接重新投递一次。
    func handle(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              let module = modules.first(where: { $0.urlSchemes.contains(scheme) }),
              module.id != activeModuleID
        else { return }

        activate(module)
        Task {
            // 模块的界面这时才刚挂载，收不到这一次的链接；等它就绪后重新打开，由它自己处理。
            try? await Task.sleep(for: .milliseconds(600))
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    var supportedOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone, activeModule?.portraitOnlyOnPhone == true {
            return .portrait
        }
        return .all
    }
}
