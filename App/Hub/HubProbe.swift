#if DEBUG
import SwiftUI
import UIKit

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
        case "uikitPagerEdgeGuard":
            return AnyView(UIKitPagerProbe(hasGuard: true).ignoresSafeArea())
        case "uikitPagerWithoutGuard":
            return AnyView(UIKitPagerProbe(hasGuard: false).ignoresSafeArea())
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

// MARK: - UIKit 的横向翻页

/// UIKit 版的同一个场景：导航控制器里推入一页，页面是整屏的横向翻页（Pica 的排行榜页和横向阅读就是这样），
/// 用来验证 `HubEdgeBackGuard`。`hasGuard` 为 false 时不装，用来做对照。
private struct UIKitPagerProbe: UIViewControllerRepresentable {
    let hasGuard: Bool

    func makeUIViewController(context: Context) -> UINavigationController {
        let root = UIViewController()
        root.view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "测试首页"
        label.accessibilityIdentifier = "probe.root"
        label.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: root.view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: root.view.centerYAnchor),
        ])

        let navigation = UINavigationController(rootViewController: root)
        // 一打开就停在推入的那一页上，这样右滑返回有地方可回。
        navigation.pushViewController(UIKitPagerProbePageController(hasGuard: hasGuard), animated: false)
        return navigation
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

private final class UIKitPagerProbePageController: UIViewController,
    UICollectionViewDataSource, UICollectionViewDelegate {
    private let hasGuard: Bool
    private let pageCount = 3
    private var taps = 0

    private let layout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        return layout
    }()

    private lazy var collectionView: UICollectionView = {
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.isPagingEnabled = true
        view.showsHorizontalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        view.dataSource = self
        view.delegate = self
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "page")
        return view
    }()

    /// 界面测试靠这两个数字判断发生了什么。
    private let pageLabel = UILabel()
    private let tapsLabel = UILabel()

    init(hasGuard: Bool) {
        self.hasGuard = hasGuard
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "测试详情"
        view.backgroundColor = .systemBackground

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        pageLabel.text = "1"
        pageLabel.accessibilityIdentifier = "probe.page"
        tapsLabel.text = "0"
        tapsLabel.accessibilityIdentifier = "probe.imageTaps"
        let labels = UIStackView(arrangedSubviews: [pageLabel, tapsLabel])
        labels.axis = .horizontal
        labels.spacing = 24
        labels.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(labels)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: labels.topAnchor, constant: -12),
            labels.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            labels.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])

        if hasGuard {
            HubEdgeBackGuard.install(on: collectionView)
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        pageCount
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "page", for: indexPath)
        cell.contentView.backgroundColor = UIColor(
            hue: CGFloat(indexPath.item) / CGFloat(pageCount), saturation: 0.45, brightness: 0.85, alpha: 1
        )
        return cell
    }

    /// 每一页和集合视图一样大。集合视图的大小要等布局完成才知道，所以在这里设。
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = collectionView.bounds.size
        if size.width > 0, size.height > 0, layout.itemSize != size {
            layout.itemSize = size
            layout.invalidateLayout()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        taps += 1
        tapsLabel.text = "\(taps)"
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.bounds.width > 0 else { return }
        let page = Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded())
        pageLabel.text = "\(min(max(page, 0), pageCount - 1) + 1)"
    }
}
#endif
