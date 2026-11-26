import ObjectiveC
import UIKit

/// 给整屏横向翻页的滚动视图让出左侧一条：手指从这一条里向右拖是「返回上一级」，不会带动翻页。
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
/// 「没接收触摸的手势不会拖住等它的手势」。第一版是那样写的，界面测试里整屏翻页不动了（当时没有分清是不是这个原因），
/// 所以改成了不指望这一点的写法。
///
/// 手势成立之后，向右拖过一小段距离就让所在的导航控制器返回上一级。只挡住翻页是不够的：界面测试里实测过，
/// 光挡住翻页时，系统的右滑返回只在贴着屏幕最边缘时才触发，从这一条的其余位置右滑什么都不会发生。
@objc(HubEdgeBackGuard)
final class HubEdgeBackGuard: NSObject, UIGestureRecognizerDelegate {
    /// 让出的宽度，和 Pixiv 多图翻页左侧让出的一样。
    static let width: CGFloat = PixivPagerEdgeGuard.width

    /// 向右拖过这么远就返回上一级。
    private static let popDistance: CGFloat = 36

    /// 关联对象的键，只用它的地址。
    private static var associationKey: UInt8 = 0

    /// 这一次拖动里是否已经触发过返回。
    private var hasPopped = false

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

    @objc private func shieldDidChange(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            hasPopped = false
        case .changed, .ended:
            guard !hasPopped, let view = recognizer.view else {
                return
            }
            let translation = recognizer.translation(in: view)
            guard translation.x >= Self.popDistance, abs(translation.x) > abs(translation.y) else {
                return
            }
            hasPopped = true
            Self.popNavigation(containing: view)
        default:
            break
        }
    }

    /// 让这个视图所在的导航控制器返回上一级。系统自己的右滑返回已经在进行时不插手。
    private static func popNavigation(containing view: UIView) {
        var responder: UIResponder? = view
        var owner: UIViewController?
        while let current = responder {
            if let controller = current as? UIViewController {
                owner = controller
                break
            }
            responder = current.next
        }
        guard let navigation = owner?.navigationController,
              navigation.viewControllers.count > 1,
              navigation.transitionCoordinator == nil
        else {
            return
        }
        if let systemPop = navigation.interactivePopGestureRecognizer,
           systemPop.state == .began || systemPop.state == .changed {
            return
        }
        navigation.popViewController(animated: true)
    }

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

    /// 不妨碍别的手势，尤其是系统自己的右滑返回。
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
