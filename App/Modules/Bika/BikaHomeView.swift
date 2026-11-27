import Observation
import SwiftUI

/// 首页要显示的东西：分类和「大家都在搜」。取一次之后留着，切到别的应用再回来不用重新取。
@Observable
final class BikaHomeModel {
    static let shared = BikaHomeModel()

    private(set) var categories: [BikaCategory] = []
    private(set) var keywords: [String] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private init() {}

    func loadIfNeeded() async {
        guard categories.isEmpty, !isLoading else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        let service = BikaSession.shared.service
        do {
            // 接口返回的分类里混着几个网页链接（官方客户端里的广告位和外链），不是漫画分类，去掉。
            categories = try await service.categories().filter { !$0.isWeb && !$0.title.isEmpty }
        } catch is CancellationError {
            // 页面离开了，不算出错。
        } catch {
            errorMessage = error.localizedDescription
        }
        // 搜索词取不到不影响使用，不提示。
        if let words = try? await service.keywords() {
            var seen = Set<String>()
            keywords = words.filter { !$0.isEmpty && seen.insert($0).inserted }
        }
        isLoading = false
    }

    /// 换了账号或者换了数据来源：把留着的东西清掉。
    func reset() {
        categories = []
        keywords = []
        errorMessage = nil
        isLoading = false
    }
}

/// 首页：搜索、几个常用入口、「大家都在搜」、分类。
struct BikaHomeView: View {
    private let model = BikaHomeModel.shared
    private let session = BikaSession.shared

    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 170), spacing: 14, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                shortcuts

                if !model.keywords.isEmpty {
                    keywordSection
                }

                categorySection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .navigationTitle("哔咔")
        .searchable(text: $searchText, prompt: "搜索漫画")
        .onSubmit(of: .search) {
            search(searchText)
        }
        .task {
            await model.loadIfNeeded()
        }
        .refreshable {
            await model.reload()
        }
    }

    // MARK: 常用入口

    private var shortcuts: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                session.selectedTab = .rank
            } label: {
                BikaShortcutLabel(title: "排行榜", systemImage: "chart.bar.fill")
            }
            .accessibilityIdentifier("bika.home.rank")

            NavigationLink(value: BikaRoute.comics(BikaComicQuery(kind: .random))) {
                BikaShortcutLabel(title: "随机本子", systemImage: "shuffle")
            }
            .accessibilityIdentifier("bika.home.random")

            NavigationLink(value: BikaRoute.comics(BikaComicQuery(kind: .all))) {
                BikaShortcutLabel(title: "最近更新", systemImage: "clock.fill")
            }
            .accessibilityIdentifier("bika.home.latest")

            NavigationLink(value: BikaRoute.comics(BikaComicQuery(kind: .favourites))) {
                BikaShortcutLabel(title: "我的收藏", systemImage: "heart.fill")
            }
            .accessibilityIdentifier("bika.home.favourites")
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    // MARK: 大家都在搜

    private var keywordSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HubSectionTitle("大家都在搜")

            FlowLayout(spacing: 8) {
                ForEach(model.keywords, id: \.self) { word in
                    Button {
                        search(word)
                    } label: {
                        Text(word)
                            .font(.subheadline)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 分类

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HubSectionTitle("分类")

            if !model.categories.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(model.categories) { category in
                        NavigationLink(value: BikaRoute.comics(BikaComicQuery(kind: .category(category.title)))) {
                            BikaCategoryCell(category: category)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("bika.category.\(category.id)")
                    }
                }
            } else if let message = model.errorMessage {
                BikaFailureView(message: message) {
                    Task { await model.reload() }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        }
    }

    private func search(_ text: String) {
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        session.homePath.append(.comics(BikaComicQuery(kind: .search(keyword))))
    }
}

/// 首页上的一个常用入口：图标在上，名字在下。
private struct BikaShortcutLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
    }
}

/// 首页上的一个分类：方的封面，下面是名字。
private struct BikaCategoryCell: View {
    let category: BikaCategory

    var body: some View {
        VStack(spacing: 7) {
            Color(uiColor: .secondarySystemFill)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    BikaRemoteImage(url: category.thumb?.url)
                }
                .pixivCover()
                .accessibilityHidden(true)

            Text(category.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .contentShape(.rect)
    }
}
