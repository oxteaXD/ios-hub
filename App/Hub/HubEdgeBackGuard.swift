import ObjectiveC
import UIKit

/// 给横向翻页的滚动视图让出左侧一条：手指从这一条里开始的横向拖动不会带动它，留给系统的右滑返回。
/// 竖向拖动、轻点、长按都不受影响，这一条以外的地方照常翻页。
///
/// 用在 UIKit 写的界面上（SwiftUI 的翻页用 `PixivPagerEdgeGuard`）。Pica 是 Objective-C 写的，而且按需载入、
/// 没有和主程序链接，所以它按类名调用这里：`installOnScrollView:`，见 `PicaKit/Host/PCHubHost.m`。
///
/// 做法：给滚动视图加一个拖动手势，并让滚动视图自己的拖动手势等它有了结论之后才能开始。这个手势只在
/// 「从左侧那一条里开始、而且是横向」的拖动上成立，成立时滚动视图就不动；其余情况它在手指刚开始移动时就宣告失败，
/// 滚动视图随即照常工作。
///
/// 它每一次触摸都参与，靠「是否成立」来区分，而不是靠「只接收从那一条里开始的触摸」。后一种写法要指望
/// 「没接收触摸的手势不会拖住等它的手势」；第一版就是那样写的，界面测试里整屏翻页不动了，所以改成不指望这一点的写法。
@objc(HubEdgeBackGuard)
final class HubEdgeBackGuard: NSObject, UIGestureRecognizerDelegate {
    /// 让出的宽度，和 Pixiv 多图翻页左侧让出的一样。
    static let width: CGFloat = PixivPagerEdgeGuard.width

    /// 关联对象的键，只用它的地址。
    private static var associationKey: UInt8 = 0

    @objc(installOnScrollView:)
    static func install(on scrollView: UIScrollView) {
        guard objc_getAssociatedObject(scrollView, &associationKey) == nil else {
            return
        }
        let guardian = HubEdgeBackGuard()
        let shield = UIPanGestureRecognizer(target: guardian, action: #selector(shieldDidChange(_:)))
        shield.delegate = guardian
        shield.cancelsTouchesInView = false
        shield.delaysTouchesBegan = false
        shield.delaysTouchesEnded = false
        scrollView.addGestureRecognizer(shield)
        scrollView.panGestureRecognizer.require(toFail: shield)
        // 让滚动视图持有它，跟着滚动视图一起释放。
        objc_setAssociatedObject(scrollView, &associationKey, guardian, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// 这个手势成立本身就是目的，成立之后不需要做任何事。
    @objc private func shieldDidChange(_ recognizer: UIPanGestureRecognizer) {}

    // MARK: UIGestureRecognizerDelegate

    /// 只在「从左侧那一条里开始的横向拖动」上成立。返回 false 时它当场宣告失败，等着它的滚动视图随即开始滚动。
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              let view = pan.view,
              let window = view.window
        else {
            return false
        }
        // 手指按下的位置 = 现在的位置 − 已经拖过的距离。
        let startX = pan.location(in: window).x - pan.translation(in: window).x
        guard startX <= Self.width else {
            return false
        }
        let velocity = pan.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y)
    }

    /// 不妨碍别的手势，尤其是导航的右滑返回。
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
