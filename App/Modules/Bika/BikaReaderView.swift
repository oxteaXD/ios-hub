import Kingfisher
import Observation
import SwiftUI

/// 阅读页的数据：现在看的是哪一话，这一话已经取到了哪些图片。
@Observable
final class BikaReaderModel {
    let target: BikaReadingTarget

    private(set) var order: Int
    private(set) var pictures: [BikaPicture] = []
    /// 这一话的图片取到了第几页（接口一页给几十张）；还没取过是 0。
    private(set) var picturePage = 0
    private(set) var picturePages = 1
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// 各张图的宽除以高。图片出来之后才知道，出来之前先按竖长的比例占位。
    private(set) var aspectRatios: [String: CGFloat] = [:]

    /// 每换一话加一，迟到的旧结果靠它认出来丢掉。
    @ObservationIgnored private var generation = 0
    /// 正在进行的那一次取图。同时来要下一页的都等它，不各取各的。
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(target: BikaReadingTarget) {
        self.target = target
        self.order = max(target.order, 1)
    }

    var episodeTitle: String {
        BikaFormat.episodeTitle(target.episodeTitles[order], order: order)
    }

    var hasMore: Bool {
        picturePage < picturePages
    }

    var hasPreviousEpisode: Bool {
        order > 1
    }

    var hasNextEpisode: Bool {
        order < target.lastOrder
    }

    /// 这一话一共多少张。
    var pictureCount: Int {
        max(total, pictures.count)
    }

    /// 刚进来：一页一页取，取到上次看到的那一张为止。
    func start() async {
        guard picturePage == 0 else { return }
        let wanted = order == target.order ? target.pictureIndex : 0
        while !Task.isCancelled {
            let before = pictures.count
            await loadMore()
            // 没取到新的（出错了、到头了）就停，免得空转。
            if pictures.count == before || pictures.count > wanted || !hasMore {
                break
            }
        }
    }

    /// 取下一页图片。已经有一次在取的话，等那一次取完。
    func loadMore() async {
        if let loadTask {
            await loadTask.value
            return
        }
        guard picturePage == 0 || hasMore else { return }
        let task = Task {
            await performLoad()
        }
        loadTask = task
        await task.value
        if loadTask == task {
            loadTask = nil
        }
    }

    private func performLoad() async {
        let current = generation
        isLoading = true
        errorMessage = nil
        do {
            let result = try await BikaSession.shared.service.pictures(
                comicID: target.comicID, order: order, page: picturePage + 1
            )
            guard current == generation else { return }
            let known = Set(pictures.map(\.id))
            pictures += result.docs.filter { !known.contains($0.id) }
            picturePage += 1
            picturePages = max(result.pages, picturePage)
            total = result.total
        } catch is CancellationError {
            // 页面离开或者换了一话，不算出错。
        } catch {
            guard current == generation else { return }
            errorMessage = error.localizedDescription
        }
        if current == generation {
            isLoading = false
        }
    }

    /// 换到另一话，从头取。
    func open(order newOrder: Int) async {
        guard newOrder >= 1, newOrder <= target.lastOrder, newOrder != order else { return }
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        order = newOrder
        pictures = []
        picturePage = 0
        picturePages = 1
        total = 0
        errorMessage = nil
        isLoading = false
        aspectRatios = [:]
        await loadMore()
    }

    func noteSize(_ size: CGSize, for id: String) {
        guard size.width > 0, size.height > 0, aspectRatios[id] == nil else { return }
        aspectRatios[id] = size.width / size.height
    }
}

/// 阅读页：一话的图片从上到下连着排，往下滑着看，滑到底自动取后面的。
///
/// 导航栏一直留着，所以从屏幕左边缘右滑随时能返回。轻点画面收起或者露出底部的翻话条。
struct BikaReaderView: View {
    @State private var model: BikaReaderModel
    @State private var showsControls = true
    /// 现在排在屏幕最上面的那张图的编号。
    @State private var position: String?
    /// 进来之后有没有处理过「回到上次看到的地方」。处理之前不记进度，免得把上次的位置冲掉。
    @State private var hasRestoredPosition = false

    init(target: BikaReadingTarget) {
        _model = State(initialValue: BikaReaderModel(target: target))
    }

    private var currentIndex: Int? {
        guard let position else { return nil }
        return model.pictures.firstIndex { $0.id == position }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.pictures.enumerated()), id: \.element.id) { index, picture in
                    BikaReaderPage(model: model, picture: picture, index: index)
                }

                footer
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $position, anchor: .top)
        .background(Color(uiColor: .systemBackground))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showsControls.toggle()
            }
        }
        .overlay(alignment: .bottom) {
            if showsControls {
                controls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(model.episodeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await model.start()
            restorePosition()
        }
        .onChange(of: position) { _, _ in
            saveProgress()
        }
        .onDisappear {
            saveProgress()
        }
    }

    // MARK: 最下面：取下一页、出错、这一话看完了

    private var footer: some View {
        VStack(spacing: 12) {
            if let message = model.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("重试") {
                    Task { await model.loadMore() }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("bika.reader.retry")
            } else if model.hasMore || model.isLoading {
                ProgressView()
                    // 每取完一页再看一次：这一行一直露着的话不会「再次出现」。
                    .task(id: model.picturePage) {
                        await model.loadMore()
                    }
            } else {
                Text("这一话看完了")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("bika.reader.end")
                if model.hasNextEpisode {
                    Button {
                        open(model.order + 1)
                    } label: {
                        Label("下一话", systemImage: "chevron.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("bika.reader.next")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        // 给底部的翻话条留出位置。
        .padding(.bottom, 96)
    }

    // MARK: 底部的翻话条

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                open(model.order - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
            }
            .disabled(!model.hasPreviousEpisode)
            .accessibilityLabel(Text("上一话"))

            Text(progressText)
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("bika.reader.progress")

            Button {
                open(model.order + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
            }
            .disabled(!model.hasNextEpisode)
            .accessibilityLabel(Text("下一话"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, 32)
        .padding(.bottom, 10)
    }

    private var progressText: String {
        guard model.pictureCount > 0 else {
            return model.episodeTitle
        }
        return "\(model.episodeTitle)　\((currentIndex ?? 0) + 1) / \(model.pictureCount)"
    }

    // MARK: 位置和进度

    private func restorePosition() {
        guard !hasRestoredPosition else { return }
        hasRestoredPosition = true
        let index = model.target.pictureIndex
        if index > 0, model.order == model.target.order, model.pictures.indices.contains(index) {
            position = model.pictures[index].id
        }
    }

    private func saveProgress() {
        guard hasRestoredPosition, let index = currentIndex else { return }
        BikaHistory.shared.saveProgress(
            comicID: model.target.comicID, order: model.order,
            episodeTitle: model.episodeTitle, pictureIndex: index
        )
    }

    private func open(_ order: Int) {
        Task {
            await model.open(order: order)
            position = model.pictures.first?.id
        }
    }
}

/// 阅读页里的一张图：宽度铺满，高度按图片自己的比例来。
private struct BikaReaderPage: View {
    let model: BikaReaderModel
    let picture: BikaPicture
    let index: Int

    var body: some View {
        // 比例在这里读，而不是由外面传进来：一张图出来了，只有露着的这几张需要重画。
        let ratio = model.aspectRatios[picture.id] ?? 0.7
        Group {
            if let url = picture.media?.url {
                KFImage(url)
                    .placeholder {
                        pageNumberPlate
                    }
                    .downloader(BikaImages.downloader)
                    .retry(maxCount: 2, interval: .seconds(1))
                    .onSuccess { result in
                        model.noteSize(
                            CGSize(width: result.image.size.width, height: result.image.size.height),
                            for: picture.id
                        )
                    }
                    .fade(duration: 0.15)
                    .resizable()
                    .aspectRatio(ratio, contentMode: .fit)
            } else {
                pageNumberPlate
                    .aspectRatio(ratio, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(Text("第 \(index + 1) 页"))
        .accessibilityIdentifier("bika.reader.page.\(index)")
    }

    /// 图片没出来之前：一块浅灰，中间是页码。
    private var pageNumberPlate: some View {
        Color(uiColor: .secondarySystemBackground)
            .overlay {
                Text(String(index + 1))
                    .font(.title.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
    }
}
