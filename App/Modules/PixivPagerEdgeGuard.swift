import SwiftUI

/// 盖在多图翻页区域左侧的一条透明区域。
///
/// 手指从这条区域里开始的横向滑动不会被翻页接走，于是系统的右滑返回能正常触发；
/// 上下滑动仍然滚动页面，轻点仍然打开大图。用在插画详情页的多图翻页上，改动见
/// `patches/pixiv/hub-detail-swipe.patch`。
struct PixivPagerEdgeGuard: View {
    /// 让出的宽度，大约一指宽。
    static let width: CGFloat = 44

    /// 轻点这条区域时要做的事，和轻点图片本身一致。
    let onTap: () -> Void

    var body: some View {
        Color.clear
            .frame(width: Self.width)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityHidden(true)
    }
}

#Preview("翻页左侧让出区域") {
    Color.gray
        .frame(height: 240)
        .overlay(alignment: .leading) {
            PixivPagerEdgeGuard {}
                .background(Color.red.opacity(0.3))
        }
}
