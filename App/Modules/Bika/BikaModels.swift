import Foundation

// 哔咔接口返回的数据。字段名照上游客户端的模型（upstream/Pica 的各个 Model 类）来。
//
// 接口没法在云端实测，所以解码一律从宽：字段缺了、类型不对都当作没有，不让一个字段的问题毁掉一整页。
// 只有每个接口最外面那一层（见文件末尾的各个 `…Data`）缺了才算出错。

// MARK: - 解码时的小工具

extension KeyedDecodingContainer {
    nonisolated func bikaString(_ key: Key) -> String? {
        try? decodeIfPresent(String.self, forKey: key)
    }

    /// 数字有时是数字，有时是带引号的数字（评论接口的页码就是）。
    nonisolated func bikaInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(exactly: value.rounded())
        }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return Int(text)
        }
        return nil
    }

    nonisolated func bikaBool(_ key: Key) -> Bool {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        return false
    }

    nonisolated func bikaStrings(_ key: Key) -> [String] {
        (try? decodeIfPresent([String].self, forKey: key)) ?? []
    }

    /// 时间是 `2020-11-07T12:48:32.393Z` 这样的文字。
    nonisolated func bikaDate(_ key: Key) -> Date? {
        guard let text = bikaString(key) else { return nil }
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(text)
    }

    nonisolated func bikaValue<Value: Decodable>(_ type: Value.Type, _ key: Key) -> Value? {
        try? decodeIfPresent(type, forKey: key)
    }

    /// 一组东西：里面个别元素读不出来就跳过，不影响其余的。
    nonisolated func bikaList<Element: Decodable>(_ type: Element.Type, _ key: Key) -> [Element]? {
        (try? decodeIfPresent(BikaLossyList<Element>.self, forKey: key))?.elements
    }
}

/// 逐个读取的数组：读不出来的元素跳过。
nonisolated struct BikaLossyList<Element: Decodable>: Decodable {
    var elements: [Element] = []

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // 读失败时位置不会往前走，用一个什么都能读的类型把这个元素跳过去。
                _ = try? container.decode(BikaSkipped.self)
            }
        }
    }
}

private nonisolated struct BikaSkipped: Decodable {}

// MARK: - 图片

/// 一张图片的位置：服务器地址加路径。封面、头像、漫画的每一页都是这个结构。
nonisolated struct BikaImage: Codable, Hashable, Sendable {
    var originalName: String?
    var path: String?
    var fileServer: String?

    /// 拼法和上游一样：服务器地址里已经带着 `static`（或者是聊天室那个域名）就直接接路径，否则中间加一段 `static`。
    var url: URL? {
        guard var server = fileServer, let path, !server.isEmpty, !path.isEmpty else { return nil }
        while server.hasSuffix("/") {
            server.removeLast()
        }
        if server.contains("static") || server.contains("bidobido") {
            return URL(string: "\(server)/\(path)")
        }
        return URL(string: "\(server)/static/\(path)")
    }
}

// MARK: - 分类

nonisolated struct BikaCategory: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var summary: String?
    var thumb: BikaImage?
    /// 这一项不是漫画分类，而是一个网页链接（官方客户端里的广告位和外链）。
    var isWeb: Bool
    var link: String?

    private enum CodingKeys: String, CodingKey {
        case identifier = "_id"
        case title, thumb, isWeb, link
        case summary = "description"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = container.bikaString(.title) ?? ""
        // 网页链接那几项没有编号，拿标题顶上。
        id = container.bikaString(.identifier) ?? title
        summary = container.bikaString(.summary)
        thumb = container.bikaValue(BikaImage.self, .thumb)
        isWeb = container.bikaBool(.isWeb)
        link = container.bikaString(.link)
    }

    init(id: String, title: String, thumb: BikaImage? = nil) {
        self.id = id
        self.title = title
        self.summary = nil
        self.thumb = thumb
        self.isWeb = false
        self.link = nil
    }
}

// MARK: - 用户

nonisolated struct BikaUser: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var email: String?
    /// 头衔，比如「萌新」。
    var title: String?
    var slogan: String?
    var gender: String?
    var level: Int?
    var exp: Int?
    /// 今天打过卡没有。
    var isPunched: Bool
    var avatar: BikaImage?
    /// 骑士榜里用：上传了多少本。
    var comicsUploaded: Int?

    private enum CodingKeys: String, CodingKey {
        case identifier = "_id"
        case alternateIdentifier = "id"
        case name, email, title, slogan, gender, level, exp, isPunched, avatar, comicsUploaded
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.bikaString(.identifier) ?? container.bikaString(.alternateIdentifier) ?? ""
        name = container.bikaString(.name) ?? ""
        email = container.bikaString(.email)
        title = container.bikaString(.title)
        slogan = container.bikaString(.slogan)
        gender = container.bikaString(.gender)
        level = container.bikaInt(.level)
        exp = container.bikaInt(.exp)
        isPunched = container.bikaBool(.isPunched)
        avatar = container.bikaValue(BikaImage.self, .avatar)
        comicsUploaded = container.bikaInt(.comicsUploaded)
    }

    init(id: String, name: String, title: String? = nil, level: Int? = nil, isPunched: Bool = false) {
        self.id = id
        self.name = name
        self.email = nil
        self.title = title
        self.slogan = nil
        self.gender = nil
        self.level = level
        self.exp = nil
        self.isPunched = isPunched
        self.avatar = nil
        self.comicsUploaded = nil
    }
}

// MARK: - 漫画

/// 一本漫画。列表里拿到的只有前面几项，详情接口才给全。
nonisolated struct BikaComic: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var author: String?
    /// 汉化组。
    var chineseTeam: String?
    var summary: String?
    var thumb: BikaImage?
    var categories: [String]
    var tags: [String]
    var pagesCount: Int?
    /// 一共多少话。
    var epsCount: Int?
    var finished: Bool
    var likesCount: Int?
    var viewsCount: Int?
    var commentsCount: Int?
    /// 排行榜里用：上榜的那个数字。
    var leaderboardCount: Int?
    var isFavourite: Bool
    var isLiked: Bool
    var updatedAt: Date?
    var createdAt: Date?
    /// 上传的人。
    var creator: BikaUser?

    private enum CodingKeys: String, CodingKey {
        case identifier = "_id"
        case alternateIdentifier = "id"
        case title, author, chineseTeam, thumb, categories, tags, pagesCount, epsCount, finished
        case likesCount, totalLikes, viewsCount, totalViews, commentsCount, leaderboardCount
        case isFavourite, isLiked
        case summary = "description"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case creator = "_creator"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.bikaString(.identifier) ?? container.bikaString(.alternateIdentifier) ?? ""
        title = container.bikaString(.title) ?? ""
        author = container.bikaString(.author)
        chineseTeam = container.bikaString(.chineseTeam)
        summary = container.bikaString(.summary)
        thumb = container.bikaValue(BikaImage.self, .thumb)
        categories = container.bikaStrings(.categories)
        tags = container.bikaStrings(.tags)
        pagesCount = container.bikaInt(.pagesCount)
        epsCount = container.bikaInt(.epsCount)
        finished = container.bikaBool(.finished)
        // 列表里叫 totalLikes / totalViews，详情里叫 likesCount / viewsCount。
        likesCount = container.bikaInt(.likesCount) ?? container.bikaInt(.totalLikes)
        viewsCount = container.bikaInt(.viewsCount) ?? container.bikaInt(.totalViews)
        commentsCount = container.bikaInt(.commentsCount)
        leaderboardCount = container.bikaInt(.leaderboardCount)
        isFavourite = container.bikaBool(.isFavourite)
        isLiked = container.bikaBool(.isLiked)
        updatedAt = container.bikaDate(.updatedAt)
        createdAt = container.bikaDate(.createdAt)
        creator = container.bikaValue(BikaUser.self, .creator)
    }

    init(
        id: String, title: String, author: String? = nil, thumb: BikaImage? = nil,
        categories: [String] = [], tags: [String] = [], pagesCount: Int? = nil, epsCount: Int? = nil,
        finished: Bool = false, likesCount: Int? = nil, summary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.chineseTeam = nil
        self.summary = summary
        self.thumb = thumb
        self.categories = categories
        self.tags = tags
        self.pagesCount = pagesCount
        self.epsCount = epsCount
        self.finished = finished
        self.likesCount = likesCount
        self.viewsCount = nil
        self.commentsCount = nil
        self.leaderboardCount = nil
        self.isFavourite = false
        self.isLiked = false
        self.updatedAt = nil
        self.createdAt = nil
        self.creator = nil
    }
}

/// 一话。
nonisolated struct BikaEpisode: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    /// 第几话，从 1 开始。取这一话的图片用的是它，不是编号。
    var order: Int
    var updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case identifier = "_id"
        case alternateIdentifier = "id"
        case title, order
        case updatedAt = "updated_at"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        order = container.bikaInt(.order) ?? 1
        id = container.bikaString(.identifier) ?? container.bikaString(.alternateIdentifier) ?? "order-\(order)"
        title = container.bikaString(.title) ?? ""
        updatedAt = container.bikaDate(.updatedAt)
    }

    init(id: String, title: String, order: Int) {
        self.id = id
        self.title = title
        self.order = order
        self.updatedAt = nil
    }
}

/// 漫画里的一页。
nonisolated struct BikaPicture: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    var media: BikaImage?

    private enum CodingKeys: String, CodingKey {
        case identifier = "_id"
        case alternateIdentifier = "id"
        case media
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        media = container.bikaValue(BikaImage.self, .media)
        id = container.bikaString(.identifier) ?? container.bikaString(.alternateIdentifier)
            ?? media?.path ?? UUID().uuidString
    }

    init(id: String, media: BikaImage? = nil) {
        self.id = id
        self.media = media
    }
}

/// 一条评论。
nonisolated struct BikaComment: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    var content: String
    var user: BikaUser?
    var isTop: Bool
    var likesCount: Int?
    /// 这条评论下面有多少条回复。
    var repliesCount: Int?
    var createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case identifier = "_id"
        case content, isTop, likesCount
        case user = "_user"
        case repliesCount = "commentsCount"
        case createdAt = "created_at"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.bikaString(.identifier) ?? UUID().uuidString
        content = container.bikaString(.content) ?? ""
        user = container.bikaValue(BikaUser.self, .user)
        isTop = container.bikaBool(.isTop)
        likesCount = container.bikaInt(.likesCount)
        repliesCount = container.bikaInt(.repliesCount)
        createdAt = container.bikaDate(.createdAt)
    }

    init(id: String, content: String, user: BikaUser? = nil, isTop: Bool = false) {
        self.id = id
        self.content = content
        self.user = user
        self.isTop = isTop
        self.likesCount = nil
        self.repliesCount = nil
        self.createdAt = nil
    }
}

// MARK: - 分页

/// 一页结果：这一页的内容，加上现在是第几页、一共几页。漫画列表、章节、图片、评论都是这个形状。
nonisolated struct BikaPage<Item: Decodable & Sendable>: Decodable, Sendable {
    var docs: [Item]
    /// 第几页，从 1 开始。
    var page: Int
    var pages: Int
    var total: Int

    private enum CodingKeys: String, CodingKey {
        case docs, comics, page, pages, total
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 「本子推荐」那个接口里这一项叫 comics。
        docs = container.bikaList(Item.self, .docs) ?? container.bikaList(Item.self, .comics) ?? []
        page = container.bikaInt(.page) ?? 1
        pages = container.bikaInt(.pages) ?? 1
        total = container.bikaInt(.total) ?? docs.count
    }

    init(docs: [Item], page: Int = 1, pages: Int = 1, total: Int? = nil) {
        self.docs = docs
        self.page = page
        self.pages = pages
        self.total = total ?? docs.count
    }

    var hasMore: Bool {
        page < pages
    }
}

// MARK: - 各接口的 data

nonisolated struct BikaTokenData: Decodable {
    let token: String
}

nonisolated struct BikaUserData: Decodable {
    let user: BikaUser
}

nonisolated struct BikaUsersData: Decodable {
    let users: BikaLossyList<BikaUser>
}

nonisolated struct BikaCategoriesData: Decodable {
    let categories: BikaLossyList<BikaCategory>
}

nonisolated struct BikaKeywordsData: Decodable {
    let keywords: [String]
}

/// 漫画列表、搜索、收藏：`comics` 是一页结果。
nonisolated struct BikaComicPageData: Decodable {
    let comics: BikaPage<BikaComic>
}

/// 排行榜、随机、相关推荐：`comics` 直接是一组漫画，不分页。
nonisolated struct BikaComicListData: Decodable {
    let comics: BikaLossyList<BikaComic>
}

nonisolated struct BikaComicData: Decodable {
    let comic: BikaComic
}

nonisolated struct BikaEpisodePageData: Decodable {
    let eps: BikaPage<BikaEpisode>
}

nonisolated struct BikaPicturePageData: Decodable {
    let pages: BikaPage<BikaPicture>
    let ep: BikaEpisode?
}

/// 收藏、喜欢：`action` 说的是这一下做了什么（`favourite` / `un_favourite`，`like` / `unlike`）。
nonisolated struct BikaActionData: Decodable {
    let action: String?
}

nonisolated struct BikaPunchData: Decodable {
    nonisolated struct Outcome: Decodable {
        /// `ok` 是打上了，`fail` 是今天已经打过。
        let status: String?
    }

    let res: Outcome?
}

nonisolated struct BikaCommentPageData: Decodable {
    let comments: BikaPage<BikaComment>
    let topComments: BikaLossyList<BikaComment>?
}

// MARK: - 请求里用到的选项

/// 列表的排序方式。括号里是接口认的写法。
nonisolated enum BikaSort: String, CaseIterable, Hashable, Sendable {
    case newest = "dd"
    case oldest = "da"
    case mostLiked = "ld"
    case mostViewed = "vd"

    var title: String {
        switch self {
        case .newest: "新到旧"
        case .oldest: "旧到新"
        case .mostLiked: "最多爱心"
        case .mostViewed: "最多指名"
        }
    }
}

/// 排行榜的时间范围。
nonisolated enum BikaRankRange: String, CaseIterable, Hashable, Sendable {
    case day = "H24"
    case week = "D7"
    case month = "D30"

    var title: String {
        switch self {
        case .day: "24 小时"
        case .week: "7 天"
        case .month: "30 天"
        }
    }
}

/// 一个漫画列表要的是什么。
nonisolated struct BikaComicQuery: Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        /// 不带条件，全部漫画。
        case all
        case category(String)
        case tag(String)
        case author(String)
        /// 汉化组。
        case translator(String)
        /// 某个人上传的。
        case uploader(id: String, name: String)
        case search(String)
        case favourites
        case random
    }

    var kind: Kind

    var title: String {
        switch kind {
        case .all: "全部漫画"
        case .category(let name): name
        case .tag(let name): name
        case .author(let name): name
        case .translator(let name): name
        case .uploader(_, let name): name
        case .search(let keyword): keyword
        case .favourites: "我的收藏"
        case .random: "随机本子"
        }
    }

    /// 随机没有排序，也没有下一页。
    var isSortable: Bool {
        kind != .random
    }
}
