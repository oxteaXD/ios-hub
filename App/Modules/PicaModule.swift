import SwiftUI
import UIKit

/// Pica（哔咔漫画客户端）的接入层。
///
/// Pica 是 Objective-C 写的 UIKit 应用。它的代码和它依赖的库都编成了动态框架放在安装包里，但主程序
/// **不链接**它们，第一次进入 Pica 时才载入。原因是它依赖的 QMUIKit 一载入就会改写一大批系统界面方法，
/// 而且对整个进程生效：不打开 Pica 的时候，另外两个应用不应该受它影响。
/// 载入之后这些改写在本次运行期间一直存在，彻底退出 App 再打开才会恢复原样。
///
/// Pica 那一侧的入口是 `PicaKit/Host/PCHubHost`（Objective-C）。因为没有链接，这里按类名找到它，
/// 通过 Objective-C 运行时取值，不能直接写类型名。
enum PicaModule {
    static let id = "pica"

    /// 载入失败的原因；成功或者还没试过时为 nil。
    private(set) static var loadFailure: String?
    private static var host: NSObject?

    /// 这次运行里是否已经把 Pica 载入进程。
    static var isLoaded: Bool {
        host != nil
    }

    /// 承载 Pica 全部界面的控制器。第一次调用时载入框架，并完成 Pica 自己的启动
    /// （相当于它单独运行时应用代理在启动时做的事）。
    static func rootViewController() -> UIViewController? {
        guard let host = loadHost() else { return nil }
        guard let controller = host.value(forKey: "rootViewController") as? UIViewController else {
            loadFailure = "PicaKit 没有给出界面"
            return nil
        }
        return controller
    }

    /// Pica 那一侧给出的自检信息，界面测试会读取它。
    static var diagnostics: String {
        (host?.value(forKey: "diagnostics") as? String) ?? "尚未载入"
    }

    private static func loadHost() -> NSObject? {
        if let host {
            return host
        }
        guard loadFailure == nil else {
            return nil
        }

        guard let frameworks = Bundle.main.privateFrameworksURL,
              let bundle = Bundle(url: frameworks.appendingPathComponent("PicaKit.framework"))
        else {
            loadFailure = "安装包里没有 PicaKit.framework"
            return nil
        }
        do {
            try bundle.loadAndReturnError()
        } catch {
            loadFailure = "载入 PicaKit 失败：\(error.localizedDescription)"
            return nil
        }

        // 类对象本身也是对象，可以向它发消息取类属性 sharedHost。
        let sharedHostSelector = NSSelectorFromString("sharedHost")
        guard let hostClass = NSClassFromString("PCHubHost"),
              (hostClass as AnyObject).responds(to: sharedHostSelector),
              let shared = (hostClass as AnyObject).perform(sharedHostSelector)?.takeUnretainedValue() as? NSObject
        else {
            loadFailure = "PicaKit 里没有找到入口 PCHubHost"
            return nil
        }
        host = shared
        return shared
    }

    static let descriptor = HubModule(
        id: id,
        title: "Pica",
        subtitle: "哔咔漫画客户端",
        systemImage: "book.pages.fill",
        cardColor: Color(red: 0.93, green: 0.42, blue: 0.60),
        // UIKit 写的界面，颜色由它自己的主题管理，宿主的强调色对它不起作用。
        accent: nil,
        // 上游在 Info.plist 里把整个 App 固定成浅色，它的界面没有为深色模式做过适配。
        interfaceStyle: .light,
        // 上游的 QMUI 配置只开放竖屏。
        portraitOnlyOnPhone: true,
        urlSchemes: [],
        // 它的载入和启动推迟到界面第一次出现时，见 `PicaRootView`。
        start: {},
        makeRootView: {
            AnyView(PicaRootView())
        },
        scenePhaseDidChange: nil
    )
}

/// Pica 的入口视图：把它的界面（UIKit）嵌进宿主的界面里。
struct PicaRootView: View {
    @State private var controller = PicaModule.rootViewController()
    #if DEBUG
    @State private var diagnostics = ""
    #endif

    var body: some View {
        if let controller {
            PicaContainer(controller: controller)
                // 安全区域和键盘都由它自己处理，和它独占窗口时一样。
                .ignoresSafeArea()
                #if DEBUG
                .overlay(alignment: .topLeading) {
                    // 给界面测试读的自检信息：只占一个点、透明、不接收触摸。安装包里没有这一段。
                    Text(verbatim: diagnostics)
                        .font(.system(size: 1))
                        .foregroundStyle(.clear)
                        .frame(width: 1, height: 1)
                        .clipped()
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("pica.diagnostics")
                }
                .task {
                    // 每隔一小会儿取一次：窗口相关的信息要等界面挂上窗口才准；Pica 的提示只显示一两秒，
                    // 取自检信息时那一侧会顺便把正在显示的提示记下来。
                    while !Task.isCancelled {
                        let latest = PicaModule.diagnostics
                        if latest != diagnostics {
                            diagnostics = latest
                        }
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                }
                #endif
        } else {
            ContentUnavailableView {
                Label {
                    Text(verbatim: "无法载入 Pica")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            } description: {
                Text(verbatim: PicaModule.loadFailure ?? "原因不明")
            }
            .accessibilityIdentifier("pica.loadFailure")
        }
    }
}

/// 每次挂载都交出同一个控制器：Pica 的界面状态（停在哪一页、登录页里填了什么）在切换应用时得以保留。
private struct PicaContainer: UIViewControllerRepresentable {
    let controller: UIViewController

    func makeUIViewController(context: Context) -> UIViewController {
        controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
