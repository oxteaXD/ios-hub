import Kingfisher
import Observation
import SwiftUI

// 哔咔各个页面共用的小部件。

// MARK: - 图片

enum BikaImages {
    /// 哔咔的图片单独用一个下载器。另外两个应用都改过 Kingfisher 默认下载器的配置
    /// （EhPanda 的 Cookie 和域名前置、Pixiv 的代理），这里不沾它们的，也不让它们沾这里的。
    /// 请求图片不带登录令牌：上游只在启动时给图片请求设令牌，刚登录的那一次运行里没有，图片照样出得来。
    static let downloader: ImageDownloader = {
        let downloader = ImageDownloader(name: "hub.bika")
        downloader.downloadTimeout = 30
        return downloader
    }()
}

/// 一张网络图片：没出来之前是一块浅灰。
struct BikaRemoteImage: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode = .fill

    var body: some View {
        KFImage(url)
            .placeholder {
                Color(uiColor: .secondarySystemFill)
            }
            .downloader(BikaImages.downloader)
            .fade(duration: 0.2)
            .resizable()
            .aspectRatio(contentMode: contentMode)
    }
}

/// 一张封面：固定宽度，统一的小圆角和淡阴影（和另外两个应用的封面一样）。
struct BikaCover: View {
    let image: BikaImage?
    let width: CGFloat
    /// 宽比高。漫画封面大多是 3 比 4。
    var aspectRatio: CGFloat = 0.75

    var body: some View {
        BikaRemoteImage(url: image?.url)
            .frame(width: width, height: (width / aspectRatio).rounded())
            .pixivCover()
            .accessibilityHidden(true)
    }
}

// MARK: - 列表里的一本漫画

struct BikaComicRow: View {
    let comic: BikaComic
    /// 排行榜里的名次，从 1 开始。
    var rank: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let rank {
                Text(String(rank))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(rank <= 3 ? Color.accentColor : Color.secondary)
                    .frame(minWidth: 26, alignment: .center)
                    .padding(.top, 2)
            }

            BikaCover(image: comic.thumb, width: 78)

            VStack(alignment: .leading, spacing: 5) {
                Text(comic.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let author = comic.author, !author.isEmpty {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !comic.categories.isEmpty {
                    Text(comic.categories.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    if let likes = comic.likesCount {
                        BikaStat(systemImage: "heart.fill", text: BikaFormat.count(likes))
                    }
                    if let pages = comic.pagesCount {
                        BikaStat(systemImage: "photo.on.rectangle", text: "\(pages) 页")
                    }
                    if let episodes = comic.epsCount, episodes > 1 {
                        BikaStat(systemImage: "list.number", text: "\(episodes) 话")
                    }
                    if comic.finished {
                        Text("完结")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

/// 一个小图标加一个数字。
struct BikaStat: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .imageScale(.small)
            Text(text)
        }
    }
}

nonisolated enum BikaFormat {
    /// 一万以上写成「1.2 万」。
    static func count(_ value: Int) -> String {
        guard value >= 10_000 else { return String(value) }
        let wan = Double(value) / 10_000
        return String(format: wan >= 100 ? "%.0f 万" : "%.1f 万", wan)
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }

    static func episodeTitle(_ title: String?, order: Int) -> String {
        if let title, !title.isEmpty {
            return title
        }
        return "第 \(order) 话"
    }
}

// MARK: - 加载中、出错

/// 没加载出来：说明原因，给一个重试按钮。
struct BikaFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("没有加载出来", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("重试", action: retry)
                .buttonStyle(.bordered)
        }
        .accessibilityIdentifier("bika.failure")
    }
}

/// 一页一页往下取的列表：现在有哪些、取到第几页、在不在取、出没出错。漫画列表和评论都用它。
@Observable
final class BikaPager<Item: Decodable & Sendable & Identifiable> where Item.ID == String {
    private(set) var items: [Item] = []
    /// 已经取到第几页；还没取过是 0。
    private(set) var page = 0
    private(set) var pages = 1
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var fetch: @MainActor (Int) async throws -> BikaPage<Item>
    /// 每换一次内容（重新加载、换排序）加一，迟到的旧结果靠它认出来丢掉。
    @ObservationIgnored private var generation = 0

    init(fetch: @escaping @MainActor (Int) async throws -> BikaPage<Item>) {
        self.fetch = fetch
    }

    var hasLoaded: Bool {
        page > 0
    }

    var hasMore: Bool {
        page < pages
    }

    /// 从第一页重新取。`fetch` 传了就换成新的取法（比如换了排序）。
    func reload(fetch newFetch: (@MainActor (Int) async throws -> BikaPage<Item>)? = nil) async {
        if let newFetch {
            fetch = newFetch
        }
        generation += 1
        items = []
        page = 0
        pages = 1
        total = 0
        errorMessage = nil
        isLoading = false
        await loadMore()
    }

    /// 取下一页。正在取、或者已经没有下一页时什么都不做。
    func loadMore() async {
        guard !isLoading, page == 0 || hasMore else { return }
        let current = generation
        isLoading = true
        errorMessage = nil
        do {
            let result = try await fetch(page + 1)
            guard current == generation else { return }
            let known = Set(items.map(\.id))
            items += result.docs.filter { !known.contains($0.id) }
            // 以实际取的页数为准：有的接口把页码写成文字，万一读错了也不至于卡住。
            page += 1
            pages = max(result.pages, page)
            total = result.total
        } catch is CancellationError {
            // 页面离开了，不算出错。
        } catch {
            guard current == generation else { return }
            errorMessage = error.localizedDescription
        }
        if current == generation {
            isLoading = false
        }
    }
}

/// 分页列表最下面的那一行：正在取下一页、取失败了可以重试、或者已经到底。
/// 它一露出来就去取下一页。
struct BikaPagerFooter<Item: Decodable & Sendable & Identifiable>: View where Item.ID == String {
    let pager: BikaPager<Item>

    var body: some View {
        Group {
            if let message = pager.errorMessage {
                // 第一页就没取到的话，由页面自己整页提示，这里不重复。
                if pager.hasLoaded {
                    VStack(spacing: 8) {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重试") {
                            Task { await pager.loadMore() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else if pager.hasMore || pager.isLoading {
                ProgressView()
                    // 每取完一页就再看一次：一页的内容不满一屏时，这一行一直露着，不会「再次出现」。
                    .task(id: pager.page) {
                        await pager.loadMore()
                    }
            } else if pager.hasLoaded, !pager.items.isEmpty {
                Text("到底了，共 \(pager.total) 项")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
