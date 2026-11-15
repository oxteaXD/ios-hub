import SwiftUI

/// 宿主的根视图：没有选中模块时显示启动页，选中后只挂载那一个模块的界面，外加悬浮切换按钮。
struct HubRootView: View {
    @State private var state = HubState.shared
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    /// 界面测试用启动参数要求打开的测试页面，见 `HubProbe`。只在调试构建里有。
    private let probe = HubProbe.requested
    #endif

    var body: some View {
        #if DEBUG
        if let probe {
            probe
        } else {
            content
        }
        #else
        content
        #endif
    }

    private var content: some View {
        ZStack {
            if let module = state.activeModule {
                module.makeRootView()
                    .tint(module.accent)
                    .id(module.id)

                HubSwitcherBubble(state: state)
            } else {
                HubLauncherView(state: state)
            }
        }
        .onAppear {
            state.syncWindowAppearance()
        }
        .onChange(of: scenePhase) { _, newPhase in
            state.forward(scenePhase: newPhase)
        }
        .onOpenURL { url in
            state.handle(url: url)
        }
    }
}
