import Foundation
import Observation

// MARK: - 页面之间怎么走

/// 底部的三个标签页。
nonisolated enum BikaTab: Hashable, Sendable {
    case home
    case rank
    case profile
}

/// 导航栈里能推入的页面。
nonisolated enum BikaRoute: Hashable, Sendable {
    case comics(BikaComicQuery)
    case detail(BikaComic)
    case reader(BikaReadingTarget)
    case comments(comicID: String, title: String)
    case history
    case settings
}

/// 打开阅读页时要知道的东西。
nonisolated struct BikaReadingTarget: Hashable, Sendable {
    var comicID: String
    var comicTitle: String
    /// 从第几话开始看。
    var order: Int
    /// 最后一话是第几话，也就是一共多少话。
    var lastOrder: Int
    /// 已经知道的各话的标题；没有的显示成「第 N 话」。
    var episodeTitles: [Int: String]
    /// 从这一话的第几张开始，0 起。
    var pictureIndex: Int
}

// MARK: - 登录状态和设置

/// 哔咔的登录状态、设置，以及各个标签页现在停在哪一页。整个应用只有一份。
@Observable
final class BikaSession {
    static let shared = BikaSession()

    private enum Keys {
        /// 登录令牌和分流用的是旧版界面（上游）的键：在旧版登录过，这里直接就是登录着的，反过来也一样。
        static let token = "PC_AUTHORIZATION_TOKEN"
        static let channel = "PC_API_CHANNEL"
        static let imageQuality = "hub.bika.imageQuality"
    }

    private(set) var token: String?
    /// 自己的资料。登录之后去取；取不到不影响别的功能。
    var user: BikaUser?
    private(set) var channel: String
    private(set) var imageQuality: String
    /// 给登录页看的一句话，比如「登录已经失效」。
    var notice: String?

    // 各标签页的导航栈放在这里，而不是放在页面自己身上：切到别的应用再回来，页面会重建，栈还在。
    var selectedTab = BikaTab.home
    var homePath: [BikaRoute] = []
    var rankPath: [BikaRoute] = []
    var profilePath: [BikaRoute] = []

    @ObservationIgnored var service: any BikaService = BikaLiveService()
    /// 设置保存到哪里。界面测试用假数据时是 nil：只放在内存里，不碰真的登录令牌。
    @ObservationIgnored private var store: UserDefaults? = .standard

    private init() {
        let defaults = UserDefaults.standard
        token = defaults.string(forKey: Keys.token)
        let savedChannel = defaults.string(forKey: Keys.channel) ?? ""
        channel = BikaAPI.channels.contains(savedChannel) ? savedChannel : BikaAPI.channels[0]
        let savedQuality = defaults.string(forKey: Keys.imageQuality) ?? ""
        imageQuality = BikaAPI.imageQualities.contains(savedQuality) ? savedQuality : BikaAPI.imageQualities[0]
    }

    var isSignedIn: Bool {
        token?.isEmpty == false
    }

    func signIn(account: String, password: String) async throws {
        let newToken = try await service.signIn(account: account, password: password)
        token = newToken
        store?.set(newToken, forKey: Keys.token)
        notice = nil
        await refreshProfile()
    }

    func refreshProfile() async {
        if let latest = try? await service.profile() {
            user = latest
        }
    }

    func signOut() {
        token = nil
        user = nil
        store?.removeObject(forKey: Keys.token)
        resetNavigation()
    }

    /// 回到刚进来的样子：各标签页退回根页面，留着的首页和排行榜数据清掉。
    private func resetNavigation() {
        selectedTab = .home
        homePath = []
        rankPath = []
        profilePath = []
        BikaHomeModel.shared.reset()
        BikaRankModel.shared.reset()
    }

    /// 服务器说登录令牌失效了：退回登录页，并说明原因。
    func sessionExpired() {
        guard isSignedIn else { return }
        signOut()
        notice = "登录已经失效，请重新登录"
    }

    func setChannel(_ value: String) {
        guard BikaAPI.channels.contains(value) else { return }
        channel = value
        store?.set(value, forKey: Keys.channel)
    }

    func setImageQuality(_ value: String) {
        guard BikaAPI.imageQualities.contains(value) else { return }
        imageQuality = value
        store?.set(value, forKey: Keys.imageQuality)
    }

    #if DEBUG
    /// 界面测试用：接口换成假数据，状态只放在内存里，不读也不写保存着的登录令牌和设置。
    func enterProbeMode(service: any BikaService, signedIn: Bool) {
        store = nil
        self.service = service
        token = signedIn ? "probe" : nil
        user = nil
        notice = nil
        resetNavigation()
    }
    #endif
}

// MARK: - 浏览历史和阅读进度

/// 看过的一本漫画，以及看到了哪里。
nonisolated struct BikaHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    var comicID: String
    var title: String
    var author: String?
    var thumb: BikaImage?
    /// 看到第几话。还没开始看是 nil。
    var episodeOrder: Int?
    var episodeTitle: String?
    /// 看到这一话的第几张，0 起。
    var pictureIndex: Int?
    var date: Date

    var id: String {
        comicID
    }
}

/// 浏览历史。存在本机，最近看的排在最前。
@Observable
final class BikaHistory {
    static let shared = BikaHistory()

    private static let key = "hub.bika.history"
    private static let limit = 300

    private(set) var entries: [BikaHistoryEntry] = []

    @ObservationIgnored private var store: UserDefaults? = .standard

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([BikaHistoryEntry].self, from: data) {
            entries = saved
        }
    }

    func entry(for comicID: String) -> BikaHistoryEntry? {
        entries.first { $0.comicID == comicID }
    }

    /// 打开了一本漫画：挪到最前面。以前看到哪里保持不变。
    func visit(_ comic: BikaComic) {
        var item = entry(for: comic.id) ?? BikaHistoryEntry(comicID: comic.id, title: comic.title, date: Date())
        item.title = comic.title
        item.author = comic.author ?? item.author
        item.thumb = comic.thumb ?? item.thumb
        item.date = Date()
        put(item)
    }

    /// 记下看到了哪一话的第几张。没有打开过详情页的漫画不记（那样连标题和封面都没有）。
    func saveProgress(comicID: String, order: Int, episodeTitle: String, pictureIndex: Int) {
        guard var item = entry(for: comicID) else { return }
        item.episodeOrder = order
        item.episodeTitle = episodeTitle
        item.pictureIndex = pictureIndex
        item.date = Date()
        put(item)
    }

    func remove(_ comicID: String) {
        entries.removeAll { $0.comicID == comicID }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func put(_ entry: BikaHistoryEntry) {
        var updated = entries.filter { $0.comicID != entry.comicID }
        updated.insert(entry, at: 0)
        if updated.count > Self.limit {
            updated.removeLast(updated.count - Self.limit)
        }
        entries = updated
        save()
    }

    private func save() {
        guard let store, let data = try? JSONEncoder().encode(entries) else { return }
        store.set(data, forKey: Self.key)
    }

    #if DEBUG
    /// 界面测试用：从空的开始，只放在内存里，不碰保存着的历史。
    func enterProbeMode() {
        store = nil
        entries = []
    }
    #endif
}
