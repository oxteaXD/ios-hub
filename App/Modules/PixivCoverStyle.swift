import SwiftUI

/// Pixiv 里作品封面和卡片后面垫的阴影，数值取自全应用统一的 `HubCoverStyle`。
///
/// 用的是 Pixiv 自己的 `CardShadowView`：它直接给图层指定阴影的轮廓，瀑布流里几百张卡片一起滚动时
/// 比 SwiftUI 的 `.shadow` 省。上游原来在各处把圆角 16 和阴影的参数各写了一遍，
/// `patches/pixiv/hub-unified-style.patch` 把它们都换成了这里。
struct PixivCoverShadow: View {
    var body: some View {
        CardShadowView(
            cornerRadius: HubCoverStyle.cornerRadius,
            shadowColor: HubCoverStyle.shadowColor,
            shadowRadius: HubCoverStyle.shadowRadius,
            shadowOffset: CGSize(width: 0, height: HubCoverStyle.shadowOffsetY)
        )
    }
}

extension View {
    /// 一张单独的封面图：裁成统一的小圆角，垫上统一的阴影。
    func pixivCover() -> some View {
        clipShape(HubCoverStyle.shape).background(PixivCoverShadow())
    }
}
