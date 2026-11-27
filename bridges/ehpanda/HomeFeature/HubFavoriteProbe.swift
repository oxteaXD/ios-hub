// 这个文件不属于 EhPanda 上游。
// 它由宿主工程的 scripts/prepare.py 在构建前复制进 HomeFeature 模块，只在调试构建里有内容：
// 给宿主的界面测试用的页面，摆出几个假的画廊，看收藏书签该出现的地方出现、不该出现的地方不出现。

#if DEBUG
import AppComponents
import AppModels
import Foundation
import GalleryListComponents
public import SwiftUI

public struct HubFavoriteProbeView: View {
    private let selfCheck: @MainActor () async -> String

    @State private var selfCheckResult = ""
    @State private var stateDescription = ""
    @State private var isSwapped = false

    /// - Parameter selfCheck: 解析那一侧的自检（在 ParserFeature 里，这个模块够不着，由调用的地方传进来）。
    public init(selfCheck: @escaping @MainActor () async -> String) {
        self.selfCheck = selfCheck
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 界面测试靠这两行字知道自检的结论，以及假画廊的收藏状态设好了没有。
                Text(verbatim: selfCheckResult)
                    .font(.footnote)
                    .accessibilityIdentifier("probe.favorite.selfCheck")
                Text(verbatim: stateDescription)
                    .font(.footnote)
                    .accessibilityIdentifier("probe.favorite.state")

                Button {
                    isSwapped.toggle()
                    applyStates()
                } label: {
                    Text(verbatim: "对调前两个画廊的收藏状态")
                }
                .accessibilityIdentifier("probe.favorite.swap")

                // 行样式：甲已收藏，乙没有。点上面的按钮之后反过来。
                GalleryDetailCell(gallery: Self.gallery(gid: "9000001", title: "行样式甲"))
                GalleryDetailCell(gallery: Self.gallery(gid: "9000002", title: "行样式乙"))

                // 网格样式：甲已收藏，乙没有。
                HStack(alignment: .top, spacing: 12) {
                    GalleryThumbnailCell(gallery: Self.gallery(gid: "9000003", title: "网格甲"))
                    GalleryThumbnailCell(gallery: Self.gallery(gid: "9000004", title: "网格乙"))
                }

                // 已收藏，但这一片关掉了书签（收藏夹页就是这样）。
                GalleryDetailCell(gallery: Self.gallery(gid: "9000005", title: "关掉书签的一片"))
                    .environment(\.hubShowsFavoriteRibbon, false)
            }
            .padding(.horizontal, 20)
        }
        .task {
            selfCheckResult = await selfCheck()
            applyStates()
        }
    }

    private func applyStates() {
        let favorites = HubFavorites.shared
        favorites.set("9000001", isFavorited: !isSwapped)
        favorites.set("9000002", isFavorited: isSwapped)
        favorites.set("9000003", isFavorited: true)
        favorites.set("9000004", isFavorited: false)
        favorites.set("9000005", isFavorited: true)
        stateDescription = isSwapped ? "已对调" : "初始"
    }

    private static func gallery(gid: String, title: String) -> Gallery {
        Gallery(
            gid: gid, token: "", title: title, rating: 4, tags: [], category: .doujinshi,
            uploader: "测试", pageCount: 32, postedDate: Date(timeIntervalSince1970: 1_700_000_000),
            coverURL: nil, galleryURL: nil
        )
    }
}
#endif
