// 这个文件不属于 EhPanda 上游。
// 它由宿主工程的 scripts/prepare.py 在构建前复制进 AppModels 模块，记的是「哪些画廊已经收藏了」。
// 往里记的地方由 patches/ehpanda/hub-favorite-mark.patch 改出来（列表页和详情页的解析），
// 读它的是 AppComponents 里的 HubFavoriteRibbon（封面上的黄色书签）。

import Foundation
public import Observation

/// 这次运行里见过的画廊，各自有没有被收藏。
///
/// 上游的列表数据（`Gallery`）里没有收藏状态，只有进了详情页才知道。但站点的列表页其实带着这个信息：
/// 已收藏的画廊，「发布时间」那一格会多一圈收藏夹颜色的边框。解析列表页时顺手把它记到这里，
/// 列表里就能给已收藏的画廊画上标记；在详情页收藏或者取消收藏之后这里跟着变，列表不用重新载入。
///
/// 没有存盘：每次载入列表都会重新得到一遍，存下来反而可能和站点上的实际情况对不上。
/// 只有登录之后才有数据，没登录时站点的列表页里没有收藏标记。
/// 历史记录这类不经过列表页的地方，只有这次运行里在别处见过的画廊才知道收没收藏。
@MainActor
@Observable
public final class HubFavorites {
    public static let shared = HubFavorites()

    private var favoritedGIDs: Set<String> = []

    init() {}

    public func contains(_ gid: String) -> Bool {
        favoritedGIDs.contains(gid)
    }

    public func set(_ gid: String, isFavorited: Bool) {
        // 没变就不动，免得读过它的界面白白重画一遍。
        guard favoritedGIDs.contains(gid) != isFavorited else { return }
        if isFavorited {
            favoritedGIDs.insert(gid)
        } else {
            favoritedGIDs.remove(gid)
        }
    }
}

extension HubFavorites {
    /// 记下一个画廊有没有被收藏。解析是在后台做的，所以这个方法从哪个线程调用都可以。
    public nonisolated static func note(gid: String, isFavorited: Bool) {
        Task { @MainActor in
            shared.set(gid, isFavorited: isFavorited)
        }
    }

    /// 从列表页的一个元素里认出收藏标记并记下来。
    ///
    /// 列表页里每个画廊都有一格「发布时间」，它的 id 是 `posted_<画廊编号>`（窄屏排版另有一份 `postedpop_<画廊编号>`）。
    /// 画廊已经收藏时，这一格带着 `style="border-color:…"`（收藏夹的颜色），没收藏时没有 style。
    /// 不是这一格的元素传进来会被直接忽略，调用的地方不用自己先挑。
    public nonisolated static func noteListCell(id: String?, style: String?) {
        guard let id else { return }
        for prefix in ["posted_", "postedpop_"] where id.hasPrefix(prefix) {
            let gid = id.dropFirst(prefix.count)
            guard !gid.isEmpty, gid.allSatisfy({ $0.isASCII && $0.isNumber }) else { return }
            note(gid: String(gid), isFavorited: style?.contains("border-color") == true)
            return
        }
    }
}
