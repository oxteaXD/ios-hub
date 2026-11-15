#if DEBUG
import SwiftUI

/// 只在调试构建里存在的测试页面，界面测试用启动参数 `-hub.probe <名字>` 打开。
///
/// 有些交互只出现在登录之后的页面里，界面测试到不了那里。这里把同样的界面结构单独搭出来，
/// 让界面测试能在模拟器上真正验证它。安装包（Release 构建）里没有这些代码。
enum HubProbe {
    /// 启动参数要求打开的测试页面；没有要求时是 nil。
    static var requested: AnyView? {
        switch UserDefaults.standard.string(forKey: "hub.probe") ?? "" {
        case "pagerEdgeGuard":
            return AnyView(PagerEdgeGuardProbe(hasGuard: true))
        case "pagerWithoutGuard":
            return AnyView(PagerEdgeGuardProbe(hasGuard: false))
        default:
            return nil
        }
    }
}

/// 和 Pixiv 插画详情页同样的结构：导航栈里推入一页，页面上下滚动，顶部是左右翻页的图片区，
/// 图片区左侧盖着 `PixivPagerEdgeGuard`。`hasGuard` 为 false 时不盖，用来做对照。
private struct PagerEdgeGuardProbe: View {
    let hasGuard: Bool
    /// 一打开就停在推入的那一页上，这样右滑返回有地方可回。
    @State private var path: [Int] = [1]

    var body: some View {
        NavigationStack(path: $path) {
            Text(verbatim: "测试首页")
                .accessibilityIdentifier("probe.root")
                .navigationDestination(for: Int.self) { _ in
                    PagerEdgeGuardProbeDetail(hasGuard: hasGuard)
                }
        }
    }
}

private struct PagerEdgeGuardProbeDetail: View {
    let hasGuard: Bool
    @State private var page = 0
    @State private var guardTaps = 0
    @State private var imageTaps = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                pager
                    .frame(height: 360)
                    .clipped()
                    .contextMenu {
                        Button {
                        } label: {
                            Text(verbatim: "测试菜单")
                        }
                    }

                // 界面测试靠这三个数字判断发生了什么。
                Text(verbatim: "\(page + 1)")
                    .accessibilityIdentifier("probe.page")
                Text(verbatim: "\(guardTaps)")
                    .accessibilityIdentifier("probe.guardTaps")
                Text(verbatim: "\(imageTaps)")
                    .accessibilityIdentifier("probe.imageTaps")

                // 让页面能上下滚动，和详情页一样。
                ForEach(0..<30, id: \.self) { row in
                    Text(verbatim: "第 \(row + 1) 行")
                }
            }
            .padding(.bottom)
        }
        .navigationTitle(Text(verbatim: "测试详情"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var pager: some View {
        let pages = TabView(selection: $page) {
            ForEach(0..<3, id: \.self) { index in
                Button {
                    imageTaps += 1
                } label: {
                    Color(hue: Double(index) / 3, saturation: 0.45, brightness: 0.85)
                }
                .buttonStyle(.plain)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))

        if hasGuard {
            pages.overlay(alignment: .leading) {
                PixivPagerEdgeGuard { guardTaps += 1 }
            }
        } else {
            pages
        }
    }
}
#endif
