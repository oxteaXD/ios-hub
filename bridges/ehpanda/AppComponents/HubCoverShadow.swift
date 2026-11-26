// 这个文件不属于 EhPanda 上游。
// 它由宿主工程的 scripts/prepare.py 在构建前复制进 AppComponents 模块，放的是封面后面垫的那一圈淡阴影。
// 用到它的地方由 patches/ehpanda/hub-unified-style.patch 改出来：`GalleryCover` 和缩略图格子的封面。

public import SwiftUI
public import UIKit

/// 封面后面垫的一圈淡阴影，是宿主里三个应用统一的封面样式的一部分（照着系统「图书」里书的封面）。
///
/// 数值和宿主的 `HubCoverStyle` 是同一组：圆角 5（也就是 `GalleryCover.clipShape` 的圆角）、
/// 16% 的黑色、模糊半径 5、向下偏 2。改的时候两边一起改。
///
/// 没有用 SwiftUI 的 `.shadow`：那样每一帧都要离屏渲染一遍来推算阴影的形状，列表里几十张封面一起滚动时不划算。
/// 这里直接给图层指定阴影的轮廓（`shadowPath`），省掉这一步。
///
/// 用法：垫在已经裁好圆角的封面后面，`.background(HubCoverShadow())`。封面自己要有不透明的底色，
/// 否则阴影会从封面透明的地方透出来。
public struct HubCoverShadow: UIViewRepresentable {
    public init() {}

    public func makeUIView(context: Context) -> ShadowView {
        ShadowView()
    }

    public func updateUIView(_ view: ShadowView, context: Context) {}

    public final class ShadowView: UIView {
        private static let cornerRadius: CGFloat = 5

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.16
            layer.shadowRadius = 5
            layer.shadowOffset = CGSize(width: 0, height: 2)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            // 这个方法只在大小变化时才会被调用，所以每次直接重算轮廓。
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Self.cornerRadius).cgPath
        }
    }
}
