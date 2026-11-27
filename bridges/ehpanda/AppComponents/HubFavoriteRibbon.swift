// 这个文件不属于 EhPanda 上游。
// 它由宿主工程的 scripts/prepare.py 在构建前复制进 AppComponents 模块，放的是已收藏画廊封面上的黄色书签。
// 用到它的地方由 patches/ehpanda/hub-favorite-mark.patch 改出来；哪些画廊已经收藏，记在 AppModels 的 HubFavorites 里。

import AppModels
public import SwiftUI
import UIKit

extension View {
    /// 这个画廊已经收藏的话，在封面上垂一条黄色书签。加在已经裁好圆角的封面上。
    ///
    /// - Parameters:
    ///   - gid: 画廊的编号。
    ///   - alignment: 书签挂在封面的哪个上角。右上角被分类标签占着的封面（网格里的）挂左上角。
    ///   - width: 书签的宽度，高度按比例来。
    public func hubFavoriteRibbon(
        gid: String, alignment: Alignment = .topTrailing, width: CGFloat = 12
    ) -> some View {
        modifier(HubFavoriteRibbonModifier(gid: gid, alignment: alignment, width: width))
    }
}

extension EnvironmentValues {
    /// 设成 false 的那一片界面不画收藏书签。收藏夹页里全是已收藏的，每一本都画就没有意义了。
    @Entry public var hubShowsFavoriteRibbon: Bool = true
}

private struct HubFavoriteRibbonModifier: ViewModifier {
    @Environment(\.hubShowsFavoriteRibbon) private var isEnabled

    let gid: String
    let alignment: Alignment
    let width: CGFloat

    func body(content: Content) -> some View {
        // 读了 HubFavorites，所以收藏状态一变（比如在详情页点了收藏再回来），这里会自己重画。
        let isFavorited = isEnabled && HubFavorites.shared.contains(gid)
        content
            .overlay(alignment: alignment) {
                if isFavorited {
                    HubFavoriteRibbon(width: width)
                        .padding(.horizontal, HubFavoriteRibbon.sideInset)
                        .offset(y: -HubFavoriteRibbon.overhang)
                        .transition(.opacity)
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: "已收藏"))
                        .accessibilityIdentifier("hub.favorite.\(gid)")
                }
            }
            .animation(.easeOut(duration: 0.2), value: isFavorited)
    }
}

/// 书签本体：一条竖着的丝带，下端剪出一个燕尾。
private struct HubFavoriteRibbon: View {
    /// 丝带离封面的侧边多远。
    static let sideInset: CGFloat = 9
    /// 丝带比封面的上边高出多少：像夹在书里、从书顶露出来的一小截。
    static let overhang: CGFloat = 3

    let width: CGFloat

    var body: some View {
        HubRibbonShape()
            .fill(Color.hubFavoriteYellow)
            .frame(width: width, height: (width * 1.9).rounded())
            // 封面什么颜色都有，垫一点阴影，浅色的封面上也分得出丝带的边。
            .shadow(color: .black.opacity(0.28), radius: 1.5, x: 0, y: 1)
    }
}

private struct HubRibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // 燕尾：下边的中间往上收进去。
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.42))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension Color {
    /// 收藏书签的黄色。浅色界面下用偏琥珀的黄（#F5B300），纯黄在亮的地方显得发虚；
    /// 深色界面下用亮一些的黄（#FFD60A）。
    fileprivate static let hubFavoriteYellow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.84, blue: 0.04, alpha: 1)
            : UIColor(red: 0.96, green: 0.70, blue: 0.0, alpha: 1)
    })
}
