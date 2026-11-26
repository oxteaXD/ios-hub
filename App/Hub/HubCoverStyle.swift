import SwiftUI

/// 全应用统一的封面样式，照着系统「图书」里书的封面：小圆角，加一圈很淡的阴影。
///
/// 圆角取 5，是 EhPanda 的封面本来就在用的数值，另外两个应用向它看齐。
///
/// 启动页上的「书」和 Pixiv 里的作品封面直接用这里的定义（Pixiv 的源码和宿主编在同一个目标里）。
/// EhPanda 是单独的包、Pica 是 Objective-C，用不到这个类型，它们各有一份同样的数值：
/// `bridges/ehpanda/AppComponents/HubCoverShadow.swift` 和 `PicaKit/Host/PCHubHost.m`。
/// 改这里的时候把那两处也一起改掉。
enum HubCoverStyle {
    static let cornerRadius: CGFloat = 5
    static let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    static let shadowColor = Color.black.opacity(0.16)
    static let shadowRadius: CGFloat = 5
    static let shadowOffsetY: CGFloat = 2
}

extension View {
    /// 把一张封面裁成统一的小圆角，再加上统一的淡阴影。
    func hubCover() -> some View {
        clipShape(HubCoverStyle.shape)
            .shadow(
                color: HubCoverStyle.shadowColor,
                radius: HubCoverStyle.shadowRadius,
                x: 0,
                y: HubCoverStyle.shadowOffsetY
            )
    }
}

extension Font {
    /// 全应用统一的分区标题字体，照着「图书」的排版：粗体的大字。
    /// EhPanda 自己的分区标题（`SubSection`）本来就是这个字号和字重，Pixiv 和 Pica 的补丁把它们的分区标题也改成了这样
    /// （Pica 那边写的是同样大小的固定字号，见 `PicaKit/Host/PCHubHost.m`）。
    static let hubSectionTitle: Font = .title3.bold()
}

/// 宿主自己页面里的分区标题。
struct HubSectionTitle: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.hubSectionTitle)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
