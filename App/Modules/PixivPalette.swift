import SwiftUI

/// Pixiv 官方配色。
///
/// 数值取自 pixiv.net 网页当前使用的样式变量（`--charcoal-brand`、`--charcoal-like`），
/// 浅色和深色模式下是同一组值。上游原本的主题色预设和自定义颜色不再使用，改动见
/// `patches/pixiv/hub-official-colors.patch`。
enum PixivPalette {
    /// 品牌蓝，Pixiv 界面的强调色。
    /// 宿主资源目录里的 `PixivBrand` 颜色是同一个值（它是全局强调色），改这里时要一起改。
    static let brandHex = 0x0096FA
    /// 收藏红：点亮的心形图标和「已收藏」状态。
    static let likeHex = 0xFF4060

    static let brand = Color(hex: brandHex)
    static let like = Color(hex: likeHex)
}
