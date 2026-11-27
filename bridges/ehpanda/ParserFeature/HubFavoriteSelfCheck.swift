// 这个文件不属于 EhPanda 上游。
// 它由宿主工程的 scripts/prepare.py 在构建前复制进 ParserFeature 模块，只在调试构建里有内容：
// 界面测试用它确认「解析列表页时把收藏标记记下来」这条路是通的（见 patches/ehpanda/hub-favorite-mark.patch）。

#if DEBUG
import AppModels
import Foundation
import Kanna

public enum HubFavoriteSelfCheck {
    /// 拿一小段照着站点列表页写的页面过一遍解析，再看 `HubFavorites` 里记的对不对。
    ///
    /// 页面里有两行：一行的「发布时间」那一格带着收藏标记，另一行没有。里面没有任何真实内容。
    /// 这两行缺封面、评分这些，解析不出画廊来，这里也不需要：只看收藏标记有没有被记下来。
    /// 返回一句给界面测试读的结论。
    @MainActor
    public static func run() async -> String {
        let favoritedGID = "9100001"
        let plainGID = "9100002"
        // 先把两个都设成和预期相反的状态，这样最后的结果只可能是解析时记下来的。
        HubFavorites.shared.set(favoritedGID, isFavorited: false)
        HubFavorites.shared.set(plainGID, isFavorited: true)

        let favoriteMark = #"style="border-color:#f00;background-color:rgba(240,0,0,.1)" title="Favorites 1""#
        let page = """
        <html><body><table class="itg gltc">
        \(row(gid: favoritedGID, attributes: favoriteMark, title: "甲"))
        \(row(gid: plainGID, attributes: "", title: "乙"))
        </table></body></html>
        """
        guard let document = try? Kanna.HTML(html: page, encoding: .utf8) else {
            return "收藏标记自检：没能把测试用的页面读进来"
        }
        _ = try? Parser.parseGalleries(doc: document)

        // 记录是转到主线程上排队做的，等它落地。
        for _ in 0..<50 {
            if HubFavorites.shared.contains(favoritedGID), !HubFavorites.shared.contains(plainGID) {
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        let favoritedNoted = HubFavorites.shared.contains(favoritedGID)
        let plainCleared = !HubFavorites.shared.contains(plainGID)
        HubFavorites.shared.set(favoritedGID, isFavorited: false)
        return "收藏标记自检：带标记的那一行记上了=\(favoritedNoted ? "是" : "否")，"
            + "不带标记的那一行去掉了=\(plainCleared ? "是" : "否")"
    }

    /// 列表页（紧凑排版）里的一行，只留下解析会去找的那几个元素。
    private static func row(gid: String, attributes: String, title: String) -> String {
        """
        <tr><td class="gl2c"><div><div \(attributes) onclick="popUp('about:blank',675,415)" \
        id="posted_\(gid)">2023-08-09 03:36</div></div></td>\
        <td class="gl3c glname"><div class="glink">\(title)</div></td></tr>
        """
    }
}
#endif
