#if DEBUG
import Foundation
import ObjectiveC
import SwiftUI

// 只在调试构建里有：给界面测试用的假接口和自检。真的接口要登录，云端测不了，
// 所以用一份假数据把「登录 → 首页 → 列表 → 详情 → 阅读」走一遍；请求签名则拿上游的实现来对。
// 入口在 `HubProbe`（启动参数 `-hub.probe bikaFlow` / `bikaSignature`）。

enum BikaProbe {
    private static var hasEnteredFlow = false

    /// 用假数据从登录页开始。状态只放在内存里，不碰保存着的登录令牌、设置和历史。
    static func flow() -> AnyView {
        // 宿主的根视图可能被重建，这里只在第一次把状态换成假的，之后不再重置。
        if !hasEnteredFlow {
            hasEnteredFlow = true
            BikaSession.shared.enterProbeMode(service: BikaMockService(), signedIn: false)
            BikaHistory.shared.enterProbeMode()
        }
        return AnyView(BikaRootView().tint(BikaModule.accent))
    }

    /// 请求签名的自检页。
    static func signature() -> AnyView {
        AnyView(BikaSignatureProbeView())
    }
}

// MARK: - 假接口

/// 一份假的哔咔接口。里面没有任何真实内容：漫画叫「测试漫画 1」「测试漫画 2」……图片都是空的。
/// 每个请求都故意慢一点，让「正在取」的状态也走到。
final class BikaMockService: BikaService {
    static let account = "probe"
    static let password = "probe"
    /// 列表一页 20 本，一共 3 页。
    static let comicsPerPage = 20
    static let comicPages = 3
    /// 一话的图片一页 4 张，一共 3 页。
    static let picturesPerPage = 4
    static let picturePages = 3

    private var favourites: Set<String> = []
    private var liked: Set<String> = []
    private var hasPunched = false

    private func delay() async throws {
        try await Task.sleep(for: .milliseconds(150))
    }

    private static func comic(_ number: Int) -> BikaComic {
        BikaComic(
            id: "mock-\(number)", title: "测试漫画 \(number)", author: "测试作者",
            categories: ["测试分类甲"], tags: ["标签一", "标签二"],
            pagesCount: picturesPerPage * picturePages * 2, epsCount: 2,
            finished: number.isMultiple(of: 2), likesCount: 100 + number,
            summary: "这是一段测试用的简介，没有实际内容。"
        )
    }

    private static func number(from comicID: String) -> Int {
        Int(comicID.replacingOccurrences(of: "mock-", with: "")) ?? 0
    }

    func signIn(account: String, password: String) async throws -> String {
        try await delay()
        guard account == Self.account, password == Self.password else {
            throw BikaError.server(status: 400, code: "1004", message: "invalid email or password", detail: nil)
        }
        return "probe-token"
    }

    func profile() async throws -> BikaUser {
        try await delay()
        return BikaUser(id: "mock-user", name: "测试用户", title: "萌新", level: 3, isPunched: hasPunched)
    }

    func punchIn() async throws -> Bool {
        try await delay()
        let isNew = !hasPunched
        hasPunched = true
        return isNew
    }

    func categories() async throws -> [BikaCategory] {
        try await delay()
        return ["甲", "乙", "丙"].enumerated().map { index, name in
            BikaCategory(id: "mock-category-\(index + 1)", title: "测试分类\(name)")
        }
    }

    func keywords() async throws -> [String] {
        try await delay()
        return ["测试词一", "测试词二"]
    }

    func comics(_ query: BikaComicQuery, sort: BikaSort, page: Int) async throws -> BikaPage<BikaComic> {
        try await delay()
        switch query.kind {
        case .random:
            return BikaPage(docs: (1...5).map { Self.comic(500 + $0) })
        case .favourites:
            let docs = favourites.map { Self.number(from: $0) }.sorted().map { Self.comic($0) }
            return BikaPage(docs: docs)
        default:
            let start = (page - 1) * Self.comicsPerPage
            let docs = (1...Self.comicsPerPage).map { Self.comic(start + $0) }
            return BikaPage(
                docs: docs, page: page, pages: Self.comicPages, total: Self.comicsPerPage * Self.comicPages
            )
        }
    }

    func leaderboard(_ range: BikaRankRange) async throws -> [BikaComic] {
        try await delay()
        return (1...5).map { Self.comic(700 + $0) }
    }

    func knightLeaderboard() async throws -> [BikaUser] {
        try await delay()
        return (1...3).map { BikaUser(id: "mock-knight-\($0)", name: "测试骑士 \($0)", title: "骑士", level: 9) }
    }

    func comic(id: String) async throws -> BikaComic {
        try await delay()
        var comic = Self.comic(Self.number(from: id))
        comic.isFavourite = favourites.contains(id)
        comic.isLiked = liked.contains(id)
        comic.commentsCount = 4
        return comic
    }

    func recommendations(comicID: String) async throws -> [BikaComic] {
        try await delay()
        return [Self.comic(901), Self.comic(902)]
    }

    func episodes(comicID: String, page: Int) async throws -> BikaPage<BikaEpisode> {
        try await delay()
        // 和真的接口一样，新的一话排在前面。
        return BikaPage(docs: [
            BikaEpisode(id: "\(comicID)-episode-2", title: "第二话", order: 2),
            BikaEpisode(id: "\(comicID)-episode-1", title: "第一话", order: 1),
        ])
    }

    func pictures(comicID: String, order: Int, page: Int) async throws -> BikaPage<BikaPicture> {
        try await delay()
        let start = (page - 1) * Self.picturesPerPage
        let docs = (0..<Self.picturesPerPage).map { BikaPicture(id: "\(comicID)-\(order)-\(start + $0)") }
        return BikaPage(
            docs: docs, page: page, pages: Self.picturePages, total: Self.picturesPerPage * Self.picturePages
        )
    }

    func toggleFavourite(comicID: String) async throws -> Bool {
        try await delay()
        if favourites.remove(comicID) != nil {
            return false
        }
        favourites.insert(comicID)
        return true
    }

    func toggleLike(comicID: String) async throws -> Bool {
        try await delay()
        if liked.remove(comicID) != nil {
            return false
        }
        liked.insert(comicID)
        return true
    }

    func comments(comicID: String, page: Int) async throws -> (top: [BikaComment], page: BikaPage<BikaComment>) {
        try await delay()
        let user = BikaUser(id: "mock-user-2", name: "测试读者", level: 2)
        let top = [BikaComment(id: "mock-comment-top", content: "这是一条置顶的测试评论。", user: user, isTop: true)]
        let docs = (1...3).map { BikaComment(id: "mock-comment-\($0)", content: "测试评论 \($0)", user: user) }
        return (top, BikaPage(docs: docs))
    }
}

// MARK: - 请求签名的自检

enum BikaSignatureCheck {
    /// 让上游的 Objective-C 实现和这里的 Swift 实现各算一遍请求头，逐项比较。返回一句给界面测试读的结论。
    ///
    /// 上游的实现在 PicaKit 里（`+[PCRequest headerWithUrl:method:time:]`），所以要先把它载入。
    /// 随机串由上游生成，这边拿同一个随机串、同一个时间再算；两边都算对的话，包括签名在内的每一项都应当一样。
    static func run() -> String {
        var lines: [String] = []

        // 一、文字的编码。只有文字和空格时，应当和系统给查询串编码的结果一样（上游用的就是系统的）。
        let sample = "全彩 Love Live"
        let system = sample.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        lines.append("文字编码和系统的一样：\(BikaAPI.encode(sample) == system ? "是" : "否")")

        // 二、请求头。
        let selector = NSSelectorFromString("headerWithUrl:method:time:")
        guard let frameworks = Bundle.main.privateFrameworksURL,
              let bundle = Bundle(url: frameworks.appendingPathComponent("PicaKit.framework")),
              bundle.load(),
              let requestClass = NSClassFromString("PCRequest"),
              let method = class_getClassMethod(requestClass, selector)
        else {
            lines.append("请求头：没能载入上游的实现，没法对")
            return lines.joined(separator: "；")
        }
        typealias HeaderFunction = @convention(c) (AnyClass, Selector, NSString, NSString, NSDate) -> NSDictionary
        let function = unsafeBitCast(method_getImplementation(method), to: HeaderFunction.self)

        let cases: [(path: String, method: String, fraction: Double)] = [
            ("auth/sign-in", "POST", 0.4),
            ("comics?page=2&s=ld&c=" + BikaAPI.encode("全彩"), "GET", 0.6),
            ("comics/5822a6e3ad7ede654696e482/order/1/pages?page=3", "GET", 0.5),
        ]
        var mismatches: [String] = []
        for (index, item) in cases.enumerated() {
            // 带上小数，连同「时间四舍五入成整数秒」这一步一起对。
            let date = Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 1000 + item.fraction)
            let upstream = function(
                requestClass, selector, item.path as NSString, item.method as NSString, date as NSDate
            ) as? [String: String]
            guard let upstream, let nonce = upstream["nonce"] else {
                mismatches.append("第 \(index + 1) 组上游没有给出请求头")
                continue
            }
            // 分流和登录令牌上游是自己从偏好设置里读的，这边读同样的值。
            let channel = UserDefaults.standard.string(forKey: "PC_API_CHANNEL") ?? "1"
            let token = UserDefaults.standard.string(forKey: "PC_AUTHORIZATION_TOKEN")
            let mine = BikaAPI.headers(
                path: item.path, method: item.method, time: date, nonce: nonce,
                channel: channel, imageQuality: "original", token: token
            )
            // 设备标识两边各自随机生成，不比。只报是哪一项不一样，不把值写出来。
            let names = Set(upstream.keys).union(mine.keys).subtracting(["app-uuid"])
            for name in names.sorted() where upstream[name] != mine[name] {
                mismatches.append("第 \(index + 1) 组的 \(name)")
            }
        }
        if mismatches.isEmpty {
            lines.append("请求头和上游算出来的：\(cases.count) 组全部一样（含签名）")
        } else {
            lines.append("请求头和上游不一样的地方：" + mismatches.joined(separator: "、"))
        }
        return lines.joined(separator: "；")
    }
}

private struct BikaSignatureProbeView: View {
    @State private var result = ""

    var body: some View {
        ScrollView {
            Text(verbatim: result)
                .font(.footnote)
                .padding()
                .accessibilityIdentifier("probe.bika.signature")
        }
        .task {
            result = BikaSignatureCheck.run()
        }
    }
}
#endif
