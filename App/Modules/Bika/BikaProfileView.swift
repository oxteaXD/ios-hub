import SwiftUI

// 「我的」标签页，以及从它进去的浏览历史、设置；还有漫画的评论页。

// MARK: - 我的

struct BikaProfileView: View {
    private let session = BikaSession.shared

    @State private var isPunching = false
    @State private var punchMessage: String?

    var body: some View {
        List {
            Section {
                profileHeader
            }

            Section {
                NavigationLink(value: BikaRoute.comics(BikaComicQuery(kind: .favourites))) {
                    Label("我的收藏", systemImage: "heart")
                }
                .accessibilityIdentifier("bika.profile.favourites")

                NavigationLink(value: BikaRoute.history) {
                    Label("浏览历史", systemImage: "clock")
                }
                .accessibilityIdentifier("bika.profile.history")
            }

            Section {
                NavigationLink(value: BikaRoute.settings) {
                    Label("设置", systemImage: "gearshape")
                }
                .accessibilityIdentifier("bika.profile.settings")
            }
        }
        .navigationTitle("我的")
        .refreshable {
            await session.refreshProfile()
        }
    }

    private var profileHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            BikaAvatar(image: session.user?.avatar, size: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.user?.name ?? "还没取到资料")
                    .font(.title3.bold())
                    .lineLimit(1)

                if let user = session.user {
                    Text(Self.subtitle(for: user))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let slogan = user.slogan, !slogan.isEmpty {
                        Text(slogan)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                if let punchMessage {
                    Text(punchMessage)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let user = session.user {
                Button {
                    punchIn()
                } label: {
                    Text(user.isPunched ? "已打卡" : "打卡")
                }
                .buttonStyle(.bordered)
                .disabled(user.isPunched || isPunching)
                .accessibilityIdentifier("bika.profile.punch")
            }
        }
        .padding(.vertical, 4)
    }

    private static func subtitle(for user: BikaUser) -> String {
        var parts: [String] = []
        if let level = user.level {
            parts.append("Lv.\(level)")
        }
        if let title = user.title, !title.isEmpty {
            parts.append(title)
        }
        if let exp = user.exp {
            parts.append("经验 \(exp)")
        }
        return parts.joined(separator: " · ")
    }

    private func punchIn() {
        guard !isPunching else { return }
        isPunching = true
        Task {
            do {
                let isNew = try await session.service.punchIn()
                punchMessage = isNew ? "打卡成功" : "今天已经打过卡了"
                await session.refreshProfile()
            } catch is CancellationError {
                // 页面离开了，不提示。
            } catch {
                punchMessage = error.localizedDescription
            }
            isPunching = false
        }
    }
}

// MARK: - 浏览历史

struct BikaHistoryView: View {
    private let history = BikaHistory.shared

    @State private var isConfirmingClear = false

    var body: some View {
        List {
            ForEach(history.entries) { entry in
                NavigationLink(value: BikaRoute.detail(Self.comic(from: entry))) {
                    BikaHistoryRow(entry: entry)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        history.remove(entry.comicID)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if history.entries.isEmpty {
                ContentUnavailableView("还没有看过的漫画", systemImage: "clock")
            }
        }
        .navigationTitle("浏览历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清空") {
                    isConfirmingClear = true
                }
                .disabled(history.entries.isEmpty)
            }
        }
        .confirmationDialog("清空全部浏览历史？", isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                history.clear()
            }
        } message: {
            Text("各本漫画看到哪里也会一起清掉，不能恢复。")
        }
    }

    /// 历史里只存了标题、作者、封面，够详情页先显示着，完整的由它自己去取。
    private static func comic(from entry: BikaHistoryEntry) -> BikaComic {
        BikaComic(id: entry.comicID, title: entry.title, author: entry.author, thumb: entry.thumb)
    }
}

private struct BikaHistoryRow: View {
    let entry: BikaHistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BikaCover(image: entry.thumb, width: 62)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(2)

                if let author = entry.author, !author.isEmpty {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private var progress: String {
        let day = BikaFormat.day(entry.date)
        guard let order = entry.episodeOrder else {
            return "\(day)　还没开始看"
        }
        let episode = BikaFormat.episodeTitle(entry.episodeTitle, order: order)
        return "\(day)　看到 \(episode) 第 \((entry.pictureIndex ?? 0) + 1) 页"
    }
}

// MARK: - 设置

struct BikaSettingsView: View {
    private let session = BikaSession.shared

    @State private var isConfirmingSignOut = false

    var body: some View {
        Form {
            Section {
                Picker(
                    "分流",
                    selection: Binding(
                        get: { session.channel },
                        set: { session.setChannel($0) }
                    )
                ) {
                    ForEach(BikaAPI.channels, id: \.self) { channel in
                        Text("分流 \(channel)").tag(channel)
                    }
                }
                .accessibilityIdentifier("bika.settings.channel")

                Picker(
                    "图片质量",
                    selection: Binding(
                        get: { session.imageQuality },
                        set: { session.setImageQuality($0) }
                    )
                ) {
                    ForEach(BikaAPI.imageQualities, id: \.self) { quality in
                        Text(Self.title(forQuality: quality)).tag(quality)
                    }
                }
            } footer: {
                Text("图片出不来或者很慢的时候，换一条分流试试。这两项改了之后，新打开的页面才生效。")
            }

            Section {
                Button("退出登录", role: .destructive) {
                    isConfirmingSignOut = true
                }
                .accessibilityIdentifier("bika.settings.signOut")
            } footer: {
                Text("这一套界面是新写的，功能还没有旧版全：聊天室、游戏区、下载、发评论、横向翻页这些暂时没有。需要的时候，回到启动页打开那本旧版的 Pica，两边用的是同一个登录状态。")
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("退出登录？", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                session.signOut()
            }
        } message: {
            Text("旧版的 Pica 也会一起退出。")
        }
    }

    private static func title(forQuality quality: String) -> String {
        switch quality {
        case "original": "原图"
        case "high": "高"
        case "medium": "中"
        case "low": "低"
        default: quality
        }
    }
}

// MARK: - 评论

/// 一本漫画的评论。只能看，还不能发。
struct BikaCommentsView: View {
    let comicID: String
    let title: String

    @State private var pager: BikaPager<BikaComment>

    init(comicID: String, title: String) {
        self.comicID = comicID
        self.title = title
        _pager = State(initialValue: BikaPager(fetch: Self.fetcher(comicID: comicID)))
    }

    private static func fetcher(comicID: String) -> @MainActor (Int) async throws -> BikaPage<BikaComment> {
        { page in
            let result = try await BikaSession.shared.service.comments(comicID: comicID, page: page)
            guard page == 1, !result.top.isEmpty else {
                return result.page
            }
            // 置顶的评论每一页都会带着，只在第一页把它们排到最前面。
            var pinned = result.top
            for index in pinned.indices {
                pinned[index].isTop = true
            }
            let pinnedIDs = Set(pinned.map(\.id))
            var merged = result.page
            merged.docs = pinned + merged.docs.filter { !pinnedIDs.contains($0.id) }
            return merged
        }
    }

    var body: some View {
        List {
            ForEach(pager.items) { comment in
                BikaCommentRow(comment: comment)
            }

            BikaPagerFooter(pager: pager)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .overlay {
            if pager.items.isEmpty {
                if let message = pager.errorMessage {
                    BikaFailureView(message: message) {
                        Task { await pager.loadMore() }
                    }
                } else if pager.hasLoaded, !pager.isLoading {
                    ContentUnavailableView("还没有评论", systemImage: "bubble.left")
                }
            }
        }
        .navigationTitle("评论")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await pager.reload()
        }
    }
}

private struct BikaCommentRow: View {
    let comment: BikaComment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BikaAvatar(image: comment.user?.avatar, size: 36)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(comment.user?.name ?? "匿名")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let level = comment.user?.level {
                        Text("Lv.\(level)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if comment.isTop {
                        Text("置顶")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }

                Text(comment.content)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    if let date = comment.createdAt {
                        Text(BikaFormat.day(date))
                    }
                    if let likes = comment.likesCount, likes > 0 {
                        BikaStat(systemImage: "heart", text: String(likes))
                    }
                    if let replies = comment.repliesCount, replies > 0 {
                        BikaStat(systemImage: "bubble.left", text: String(replies))
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
