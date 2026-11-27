import Foundation

/// 哔咔的各个接口。界面只认这个协议，不直接碰网络：正式运行时用 `BikaLiveService`，
/// 调试构建里的界面测试换成一份假数据（见 `BikaProbe`），因为真的接口要登录，云端测不了。
protocol BikaService {
    /// 登录，返回登录令牌。
    func signIn(account: String, password: String) async throws -> String
    func profile() async throws -> BikaUser
    /// 打卡。返回 false 表示今天已经打过了。
    func punchIn() async throws -> Bool

    func categories() async throws -> [BikaCategory]
    /// 「大家都在搜」的那些词。
    func keywords() async throws -> [String]

    /// 一个列表的某一页。随机没有分页，`page` 不起作用。
    func comics(_ query: BikaComicQuery, sort: BikaSort, page: Int) async throws -> BikaPage<BikaComic>
    func leaderboard(_ range: BikaRankRange) async throws -> [BikaComic]
    /// 骑士榜：上传得最多的人。
    func knightLeaderboard() async throws -> [BikaUser]

    func comic(id: String) async throws -> BikaComic
    /// 「看了这本的人也在看」。
    func recommendations(comicID: String) async throws -> [BikaComic]
    func episodes(comicID: String, page: Int) async throws -> BikaPage<BikaEpisode>
    /// 某一话的图片，一页一页取。`order` 是第几话。
    func pictures(comicID: String, order: Int, page: Int) async throws -> BikaPage<BikaPicture>

    /// 收藏或者取消收藏（同一个接口，来回切换）。返回切换之后是不是收藏着。
    func toggleFavourite(comicID: String) async throws -> Bool
    /// 喜欢或者取消喜欢。返回切换之后是不是喜欢着。
    func toggleLike(comicID: String) async throws -> Bool

    /// 评论的某一页。置顶的评论每一页都会带着，只在第一页用。
    func comments(comicID: String, page: Int) async throws -> (top: [BikaComment], page: BikaPage<BikaComment>)
}

/// 真的去请求哔咔服务器的那一份。路径和参数照上游客户端的各个请求类来。
struct BikaLiveService: BikaService {
    private let client = BikaClient.shared

    func signIn(account: String, password: String) async throws -> String {
        let body = ["email": account, "password": password]
        return try await client.send("POST", "auth/sign-in", body: body, as: BikaTokenData.self).token
    }

    func profile() async throws -> BikaUser {
        try await client.send("GET", "users/profile", as: BikaUserData.self).user
    }

    func punchIn() async throws -> Bool {
        let data = try await client.send("POST", "users/punch-in", as: BikaPunchData.self)
        return data.res?.status != "fail"
    }

    func categories() async throws -> [BikaCategory] {
        try await client.send("GET", "categories", as: BikaCategoriesData.self).categories.elements
    }

    func keywords() async throws -> [String] {
        try await client.send("GET", "keywords", as: BikaKeywordsData.self).keywords
    }

    func comics(_ query: BikaComicQuery, sort: BikaSort, page: Int) async throws -> BikaPage<BikaComic> {
        switch query.kind {
        case .random:
            let comics = try await client.send("GET", "comics/random", as: BikaComicListData.self).comics.elements
            return BikaPage(docs: comics)
        case .favourites:
            let path = "users/favourite?s=\(sort.rawValue)&page=\(page)"
            return try await client.send("GET", path, as: BikaComicPageData.self).comics
        case .search(let keyword):
            let body = ["keyword": keyword, "sort": sort.rawValue]
            let path = "comics/advanced-search?page=\(page)"
            return try await client.send("POST", path, body: body, as: BikaComicPageData.self).comics
        case .all:
            return try await comicList(page: page, sort: sort, filter: nil)
        case .category(let name):
            return try await comicList(page: page, sort: sort, filter: ("c", name))
        case .tag(let name):
            return try await comicList(page: page, sort: sort, filter: ("t", name))
        case .translator(let name):
            return try await comicList(page: page, sort: sort, filter: ("ct", name))
        case .uploader(let id, _):
            return try await comicList(page: page, sort: sort, filter: ("ca", id))
        case .author(let name):
            return try await comicList(page: page, sort: sort, filter: ("a", name))
        }
    }

    /// `comics?page=1&s=dd`，后面再接一个筛选条件：`c` 分类、`t` 标签、`ct` 汉化组、`ca` 上传者、`a` 作者。
    private func comicList(
        page: Int, sort: BikaSort, filter: (name: String, value: String)?
    ) async throws -> BikaPage<BikaComic> {
        var path = "comics?page=\(page)&s=\(sort.rawValue)"
        if let filter {
            path += "&\(filter.name)=\(BikaAPI.encode(filter.value))"
        }
        return try await client.send("GET", path, as: BikaComicPageData.self).comics
    }

    func leaderboard(_ range: BikaRankRange) async throws -> [BikaComic] {
        let path = "comics/leaderboard?tt=\(range.rawValue)&ct=VC"
        return try await client.send("GET", path, as: BikaComicListData.self).comics.elements
    }

    func knightLeaderboard() async throws -> [BikaUser] {
        try await client.send("GET", "comics/knight-leaderboard", as: BikaUsersData.self).users.elements
    }

    func comic(id: String) async throws -> BikaComic {
        try await client.send("GET", "comics/\(BikaAPI.encode(id))", as: BikaComicData.self).comic
    }

    func recommendations(comicID: String) async throws -> [BikaComic] {
        let path = "comics/\(BikaAPI.encode(comicID))/recommendation"
        return try await client.send("GET", path, as: BikaComicListData.self).comics.elements
    }

    func episodes(comicID: String, page: Int) async throws -> BikaPage<BikaEpisode> {
        let path = "comics/\(BikaAPI.encode(comicID))/eps?page=\(page)"
        return try await client.send("GET", path, as: BikaEpisodePageData.self).eps
    }

    func pictures(comicID: String, order: Int, page: Int) async throws -> BikaPage<BikaPicture> {
        let path = "comics/\(BikaAPI.encode(comicID))/order/\(order)/pages?page=\(page)"
        return try await client.send("GET", path, as: BikaPicturePageData.self).pages
    }

    func toggleFavourite(comicID: String) async throws -> Bool {
        let path = "comics/\(BikaAPI.encode(comicID))/favourite"
        return try await client.send("POST", path, as: BikaActionData.self).action == "favourite"
    }

    func toggleLike(comicID: String) async throws -> Bool {
        let path = "comics/\(BikaAPI.encode(comicID))/like"
        return try await client.send("POST", path, as: BikaActionData.self).action == "like"
    }

    func comments(comicID: String, page: Int) async throws -> (top: [BikaComment], page: BikaPage<BikaComment>) {
        let path = "comics/\(BikaAPI.encode(comicID))/comments?page=\(page)"
        let data = try await client.send("GET", path, as: BikaCommentPageData.self)
        return (data.topComments?.elements ?? [], data.comments)
    }
}
