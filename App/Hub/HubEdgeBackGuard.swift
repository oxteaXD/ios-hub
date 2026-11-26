import ObjectiveC
import UIKit

/// 给横向翻页的滚动视图让出左侧一条：手指从这一条里开始的横向拖动不会带动它，留给系统的右滑返回。
/// 竖向拖动、轻点、长按都不受影响，这一条以外的地方照常翻页。
///
/// 用在 UIKit 写的界面上（SwiftUI 的翻页用 `PixivPagerEdgeGuard`）。Pica 是 Objective-C 写的，而且按需载入、
/// 没有和主程序链接，所以它按类名调用这里：`installOnScrollView:`，见 `PicaKit/Host/PCHubHost.m`。
///
/// 做法：给滚动视图加一个只认「从左侧那一条开始的横向拖动」的手势，并让滚动视图自己的拖动手势等它失败之后才能开始。
/// 手指从那一条里横向拖动时，这个手势成立，滚动视图就不动；别的情况下它不成立，滚动视图照常工作。
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

    /// 只接收从左侧那一条里开始的触摸。别处开始的触摸它根本不参与，滚动视图不用等它。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let window = touch.window ?? gestureRecognizer.view?.window else {
            return false
        }
        return touch.location(in: window).x <= Self.width
    }

    /// 只认横向的拖动。竖向拖动时它不成立，滚动视图（以及外层的竖向滚动）照常处理。
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else {
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
