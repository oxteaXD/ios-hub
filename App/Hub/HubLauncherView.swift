import SwiftUI
import UIKit

/// 启动页：照着系统「图书」的排版做的一排书架——大标题、粗体的分区标题、分区之间一条细线，
/// 每个子应用是一本素色封面的书，点一下进入。
///
/// 只借用了图书的样子，没有借它的功能：这里没有书库、进度之类的东西，仍然只是一个应用列表加一个开关。
struct HubLauncherView: View {
    @Bindable var state: HubState

    /// 一排放得下几本就放几本：iPhone 竖屏是三本，横屏和 iPad 更多。
    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 150), spacing: 18, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()

                    HubSectionTitle("应用")
                        .padding(.top, 18)
                        .padding(.bottom, 14)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                        ForEach(state.modules) { module in
                            Button {
                                state.activate(module)
                            } label: {
                                HubModuleBook(module: module)
                            }
                            .buttonStyle(HubBookButtonStyle())
                            .accessibilityLabel(Text(verbatim: "\(module.title)，\(module.subtitle)"))
                            // 界面测试靠这个标识找到每一本书。
                            .accessibilityIdentifier("hub.module.\(module.id)")
                        }
                    }
                    .padding(.bottom, 28)

                    Divider()

                    HubSectionTitle("启动")
                        .padding(.top, 18)
                        .padding(.bottom, 10)

                    Toggle("启动时直接进入上次使用的应用", isOn: $state.autoEnterLastModule)

                    Text("进入应用后，轻点屏幕右侧的悬浮按钮回到这里，长按它可以直接切到别的应用，按住可以上下拖动。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                        .padding(.bottom, 28)

                    Divider()

                    Text(versionText)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 16)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            // 图书用的是纯色的底（浅色时白、深色时黑），不是设置页那种灰色的分组底色。
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Hub")
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// 一本「书」：素色的封面，下面是应用名和一句说明。
private struct HubModuleBook: View {
    let module: HubModule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubBookCover(title: module.title, systemImage: module.systemImage, color: module.cardColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(module.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 素色的书封面：2:3 的比例，左边一道书脊的折痕，左上角是应用的图形，左下角印着应用名。
private struct HubBookCover: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        color
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.top, 14)
                    .padding(.leading, 18)
            }
            .overlay(alignment: .bottomLeading) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                    .padding(.leading, 18)
                    .padding(.trailing, 8)
                    .padding(.bottom, 14)
            }
            .overlay(alignment: .leading) {
                // 书脊的折痕：一道暗线贴着一道亮线。
                HStack(spacing: 0) {
                    Rectangle().fill(.black.opacity(0.10)).frame(width: 1)
                    Rectangle().fill(.white.opacity(0.22)).frame(width: 1)
                }
                .padding(.leading, 8)
            }
            .hubCover()
    }
}

/// 按下去的时候整本书略微缩小、变淡。
private struct HubBookButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
