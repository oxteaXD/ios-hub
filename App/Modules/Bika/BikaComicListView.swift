import Observation
import SwiftUI

/// 一个漫画列表：某个分类、标签、作者、汉化组、上传者名下的漫画，搜索结果，我的收藏，随机本子，都是这一个页面。
/// 滑到底自动取下一页。
struct BikaComicListView: View {
    let query: BikaComicQuery

    @State private var sort = BikaSort.newest
    @State private var pager: BikaPager<BikaComic>

    init(query: BikaComicQuery) {
        self.query = query
        _pager = State(initialValue: BikaPager(fetch: Self.fetcher(query, sort: .newest)))
    }

    private static func fetcher(
        _ query: BikaComicQuery, sort: BikaSort
    ) -> @MainActor (Int) async throws -> BikaPage<BikaComic> {
        { page in
            try await BikaSession.shared.service.comics(query, sort: sort, page: page)
        }
    }

    var body: some View {
        List {
            ForEach(pager.items) { comic in
                NavigationLink(value: BikaRoute.detail(comic)) {
                    BikaComicRow(comic: comic)
                }
                .accessibilityIdentifier("bika.comic.\(comic.id)")
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
                    ContentUnavailableView("这里没有漫画", systemImage: "tray")
                }
            }
        }
        .navigationTitle(query.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if query.isSortable {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("排序", selection: $sort) {
                            ForEach(BikaSort.allCases, id: \.self) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    } label: {
                        Label("排序", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("bika.list.sort")
                }
            }
        }
        .onChange(of: sort) { _, newSort in
            Task {
                await pager.reload(fetch: Self.fetcher(query, sort: newSort))
            }
        }
        .refreshable {
            await pager.reload()
        }
    }
}

// MARK: - 排行榜

/// 排行榜上的四块：三个时间范围的漫画榜，加一个骑士榜（上传得最多的人）。
nonisolated enum BikaRankBoard: String, CaseIterable, Hashable, Sendable {
    case day
    case week
    case month
    case knights

    var title: String {
        switch self {
        case .day: BikaRankRange.day.title
        case .week: BikaRankRange.week.title
        case .month: BikaRankRange.month.title
        case .knights: "骑士榜"
        }
    }

    var range: BikaRankRange? {
        switch self {
        case .day: return BikaRankRange.day
        case .week: return BikaRankRange.week
        case .month: return BikaRankRange.month
        case .knights: return nil
        }
    }
}

/// 排行榜的数据。每一块取过一次就留着，下拉才重新取。
@Observable
final class BikaRankModel {
    static let shared = BikaRankModel()

    private(set) var comics: [BikaRankBoard: [BikaComic]] = [:]
    private(set) var knights: [BikaUser] = []
    private(set) var loaded: Set<BikaRankBoard> = []
    private(set) var loading: Set<BikaRankBoard> = []
    private(set) var errors: [BikaRankBoard: String] = [:]

    private init() {}

    func load(_ board: BikaRankBoard, force: Bool = false) async {
        guard force || !loaded.contains(board), !loading.contains(board) else { return }
        loading.insert(board)
        errors[board] = nil
        let service = BikaSession.shared.service
        do {
            if let range = board.range {
                comics[board] = try await service.leaderboard(range)
            } else {
                knights = try await service.knightLeaderboard()
            }
            loaded.insert(board)
        } catch is CancellationError {
            // 页面离开了，不算出错。
        } catch {
            errors[board] = error.localizedDescription
        }
        loading.remove(board)
    }

    func reset() {
        comics = [:]
        knights = []
        loaded = []
        loading = []
        errors = [:]
    }
}

struct BikaRankView: View {
    private let model = BikaRankModel.shared

    @State private var board = BikaRankBoard.day

    var body: some View {
        List {
            Picker("榜单", selection: $board) {
                ForEach(BikaRankBoard.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("bika.rank.board")

            if board == .knights {
                ForEach(Array(model.knights.enumerated()), id: \.element.id) { index, user in
                    NavigationLink(
                        value: BikaRoute.comics(BikaComicQuery(kind: .uploader(id: user.id, name: user.name)))
                    ) {
                        BikaKnightRow(user: user, rank: index + 1)
                    }
                }
            } else {
                ForEach(Array((model.comics[board] ?? []).enumerated()), id: \.element.id) { index, comic in
                    NavigationLink(value: BikaRoute.detail(comic)) {
                        BikaComicRow(comic: comic, rank: index + 1)
                    }
                    .accessibilityIdentifier("bika.rank.comic.\(comic.id)")
                }
            }

            if model.loading.contains(board) {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowSeparator(.hidden)
            } else if let message = model.errors[board] {
                BikaFailureView(message: message) {
                    Task { await model.load(board, force: true) }
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle("排行榜")
        .task(id: board) {
            await model.load(board)
        }
        .refreshable {
            await model.load(board, force: true)
        }
    }
}

/// 骑士榜上的一个人。
private struct BikaKnightRow: View {
    let user: BikaUser
    let rank: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(String(rank))
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(rank <= 3 ? Color.accentColor : Color.secondary)
                .frame(minWidth: 26, alignment: .center)

            BikaAvatar(image: user.avatar, size: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(user.name)
                    .font(.headline)
                    .lineLimit(1)
                if let title = user.title, !title.isEmpty {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let uploaded = user.comicsUploaded {
                Text("上传 \(uploaded) 本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 圆形头像。没有头像时是一个人形图标。
struct BikaAvatar: View {
    let image: BikaImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let url = image?.url {
                BikaRemoteImage(url: url)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
