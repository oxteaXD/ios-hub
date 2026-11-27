import Observation
import SwiftUI

/// 一本漫画的详情页要用的数据：漫画本身、章节、相关推荐，以及收藏和喜欢这两个开关。
@Observable
final class BikaDetailModel {
    /// 一开始是列表里那一份（只有标题、封面这些），详情取回来之后换成完整的。
    private(set) var comic: BikaComic
    private(set) var hasLoadedDetail = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private(set) var episodes: [BikaEpisode] = []
    /// 各话的标题，按第几话查。阅读页显示标题用。
    private(set) var episodeTitles: [Int: String] = [:]
    /// 章节已经取到第几页；还没取过是 0。
    private(set) var episodePage = 0
    private(set) var episodePages = 1
    private(set) var isLoadingEpisodes = false
    private(set) var episodeError: String?

    private(set) var recommendations: [BikaComic] = []

    private(set) var isUpdatingFavourite = false
    private(set) var isUpdatingLike = false
    /// 收藏、喜欢没成功时的原因，页面用一个提示框显示。
    var actionError: String?

    init(comic: BikaComic) {
        self.comic = comic
    }

    var hasMoreEpisodes: Bool {
        episodePage < episodePages
    }

    /// 最后一话是第几话。
    var lastOrder: Int {
        max(comic.epsCount ?? 0, episodes.map(\.order).max() ?? 0, 1)
    }

    func load() async {
        guard !isLoading, !hasLoadedDetail else { return }
        isLoading = true
        errorMessage = nil
        // 先按手头的信息记进历史，详情取回来再补全。
        BikaHistory.shared.visit(comic)
        let service = BikaSession.shared.service
        do {
            let detail = try await service.comic(id: comic.id)
            // 万一详情里没带编号，就不换，免得后面的请求拼不出地址。
            if detail.id == comic.id {
                comic = detail
            }
            hasLoadedDetail = true
            BikaHistory.shared.visit(comic)
        } catch is CancellationError {
            // 页面离开了，不算出错。
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false

        if episodePage == 0 {
            await loadMoreEpisodes()
        }
        if recommendations.isEmpty, let list = try? await service.recommendations(comicID: comic.id) {
            recommendations = list.filter { $0.id != comic.id }
        }
    }

    /// 详情没取到时的重试。
    func retry() async {
        hasLoadedDetail = false
        await load()
    }

    func loadMoreEpisodes() async {
        guard !isLoadingEpisodes, episodePage == 0 || hasMoreEpisodes else { return }
        isLoadingEpisodes = true
        episodeError = nil
        do {
            let result = try await BikaSession.shared.service.episodes(comicID: comic.id, page: episodePage + 1)
            let known = Set(episodes.map(\.id))
            episodes += result.docs.filter { !known.contains($0.id) }
            for episode in result.docs {
                episodeTitles[episode.order] = episode.title
            }
            episodePage += 1
            episodePages = max(result.pages, episodePage)
        } catch is CancellationError {
            // 页面离开了，不算出错。
        } catch {
            episodeError = error.localizedDescription
        }
        isLoadingEpisodes = false
    }

    func readingTarget(order: Int, pictureIndex: Int = 0) -> BikaReadingTarget {
        BikaReadingTarget(
            comicID: comic.id, comicTitle: comic.title, order: order, lastOrder: max(lastOrder, order),
            episodeTitles: episodeTitles, pictureIndex: pictureIndex
        )
    }

    func toggleFavourite() async {
        guard !isUpdatingFavourite else { return }
        isUpdatingFavourite = true
        do {
            comic.isFavourite = try await BikaSession.shared.service.toggleFavourite(comicID: comic.id)
        } catch is CancellationError {
            // 页面离开了，不提示。
        } catch {
            actionError = error.localizedDescription
        }
        isUpdatingFavourite = false
    }

    func toggleLike() async {
        guard !isUpdatingLike else { return }
        isUpdatingLike = true
        do {
            let isLiked = try await BikaSession.shared.service.toggleLike(comicID: comic.id)
            if isLiked != comic.isLiked, let count = comic.likesCount {
                comic.likesCount = max(0, count + (isLiked ? 1 : -1))
            }
            comic.isLiked = isLiked
        } catch is CancellationError {
            // 页面离开了，不提示。
        } catch {
            actionError = error.localizedDescription
        }
        isUpdatingLike = false
    }
}

/// 漫画详情页：封面和基本信息、开始或继续阅读、收藏、喜欢、评论、简介、标签、章节、相关推荐。
struct BikaComicDetailView: View {
    @State private var model: BikaDetailModel
    @State private var isSummaryExpanded = false

    private let history = BikaHistory.shared
    private let episodeColumns = [GridItem(.adaptive(minimum: 96, maximum: 200), spacing: 10)]

    init(comic: BikaComic) {
        _model = State(initialValue: BikaDetailModel(comic: comic))
    }

    private var comic: BikaComic {
        model.comic
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                actions

                if let message = model.errorMessage {
                    BikaFailureView(message: message) {
                        Task { await model.retry() }
                    }
                }

                if let summary = comic.summary, !summary.isEmpty {
                    summarySection(summary)
                }
                if !comic.tags.isEmpty {
                    tagSection
                }
                episodeSection
                if !model.recommendations.isEmpty {
                    recommendationSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .navigationTitle(comic.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
        }
        .alert(
            "没有成功",
            isPresented: Binding(
                get: { model.actionError != nil },
                set: { isPresented in
                    if !isPresented {
                        model.actionError = nil
                    }
                }
            )
        ) {
            Button("好") {}
        } message: {
            Text(model.actionError ?? "")
        }
    }

    // MARK: 封面和基本信息

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            BikaCover(image: comic.thumb, width: 116)

            VStack(alignment: .leading, spacing: 6) {
                Text(comic.title)
                    .font(.title3.bold())
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
                    .accessibilityIdentifier("bika.detail.title")

                if let author = comic.author, !author.isEmpty {
                    NavigationLink(value: BikaRoute.comics(BikaComicQuery(kind: .author(author)))) {
                        Text(author)
                            .font(.subheadline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                if let team = comic.chineseTeam, !team.isEmpty {
                    NavigationLink(value: BikaRoute.comics(BikaComicQuery(kind: .translator(team)))) {
                        Text("汉化：\(team)")
                            .font(.footnote)
                            .lineLimit(1)
                    }
                }

                if !comic.categories.isEmpty {
                    Text(comic.categories.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    if let pages = comic.pagesCount {
                        BikaStat(systemImage: "photo.on.rectangle", text: "\(pages) 页")
                    }
                    if let episodes = comic.epsCount {
                        BikaStat(systemImage: "list.number", text: "\(episodes) 话")
                    }
                    if let views = comic.viewsCount {
                        BikaStat(systemImage: "eye", text: BikaFormat.count(views))
                    }
                    if comic.finished {
                        Text("完结")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let updated = comic.updatedAt {
                    Text("更新于 \(BikaFormat.day(updated))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 阅读、收藏、喜欢、评论

    /// 看过就从上次的地方接着看，没看过从第一话开始。
    private var resumeTarget: BikaReadingTarget {
        if let entry = history.entry(for: comic.id), let order = entry.episodeOrder {
            return model.readingTarget(order: order, pictureIndex: entry.pictureIndex ?? 0)
        }
        return model.readingTarget(order: 1)
    }

    private var resumeTitle: String {
        if let entry = history.entry(for: comic.id), let order = entry.episodeOrder {
            return "接着看 " + BikaFormat.episodeTitle(entry.episodeTitle, order: order)
        }
        return "开始阅读"
    }

    private var actions: some View {
        VStack(spacing: 10) {
            NavigationLink(value: BikaRoute.reader(resumeTarget)) {
                Label(resumeTitle, systemImage: "book.fill")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("bika.detail.read")

            HStack(spacing: 10) {
                Button {
                    Task { await model.toggleFavourite() }
                } label: {
                    Label(
                        comic.isFavourite ? "已收藏" : "收藏",
                        systemImage: comic.isFavourite ? "bookmark.fill" : "bookmark"
                    )
                    .frame(maxWidth: .infinity)
                }
                .disabled(model.isUpdatingFavourite)
                .accessibilityIdentifier("bika.detail.favourite")

                Button {
                    Task { await model.toggleLike() }
                } label: {
                    Label(
                        comic.likesCount.map { BikaFormat.count($0) } ?? "喜欢",
                        systemImage: comic.isLiked ? "heart.fill" : "heart"
                    )
                    .frame(maxWidth: .infinity)
                }
                .disabled(model.isUpdatingLike)
                .accessibilityIdentifier("bika.detail.like")

                NavigationLink(value: BikaRoute.comments(comicID: comic.id, title: comic.title)) {
                    Label(
                        comic.commentsCount.map { BikaFormat.count($0) } ?? "评论",
                        systemImage: "bubble.left"
                    )
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("bika.detail.comments")
            }
            .buttonStyle(.bordered)
            .lineLimit(1)
        }
    }

    // MARK: 简介

    private func summarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HubSectionTitle("简介")

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(isSummaryExpanded ? nil : 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .onTapGesture {
                    isSummaryExpanded.toggle()
                }
        }
    }

    // MARK: 标签

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubSectionTitle("标签")

            FlowLayout(spacing: 8) {
                ForEach(comic.tags.bikaUnique(), id: \.self) { tag in
                    NavigationLink(value: BikaRoute.comics(BikaComicQuery(kind: .tag(tag)))) {
                        Text(tag)
                            .font(.footnote)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 章节

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubSectionTitle("章节")

            let current = history.entry(for: comic.id)?.episodeOrder
            LazyVGrid(columns: episodeColumns, alignment: .leading, spacing: 10) {
                ForEach(model.episodes) { episode in
                    NavigationLink(value: BikaRoute.reader(model.readingTarget(order: episode.order))) {
                        Text(BikaFormat.episodeTitle(episode.title, order: episode.order))
                            .font(.subheadline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 6)
                            .background(
                                episode.order == current
                                    ? AnyShapeStyle(TintShapeStyle().opacity(0.18))
                                    : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)),
                                in: .rect(cornerRadius: 8)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("bika.episode.\(episode.order)")
                }
            }

            if model.isLoadingEpisodes {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else if let message = model.episodeError {
                VStack(spacing: 8) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("重试") {
                        Task { await model.loadMoreEpisodes() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
            } else if model.hasMoreEpisodes {
                Button("更多章节") {
                    Task { await model.loadMoreEpisodes() }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: 相关推荐

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubSectionTitle("看了这本的人也在看")

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(model.recommendations) { other in
                        NavigationLink(value: BikaRoute.detail(other)) {
                            VStack(alignment: .leading, spacing: 6) {
                                BikaCover(image: other.thumb, width: 96)
                                Text(other.title)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: 96, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                // 给封面的阴影留出位置，不然会被横向滚动的边界裁掉。
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
        }
    }
}

extension Array where Element: Hashable {
    /// 去掉重复的，保持原来的先后。
    func bikaUnique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
