// 这个文件不属于 EhPanda 上游。
// 它由宿主工程的 scripts/prepare.py 在构建前复制进 HomeFeature 模块，放的是主页上
// 「不显示 AI 作品」和「AI 热门入口」这两处新增内容里，不需要改动上游文件的部分。

import AppModels
import AppTools
import ComposableArchitecture
import SwiftUI
import UIKit

// MARK: 顶部大卡片

extension HomeClient {
    /// 顶部大卡片最多显示几个。
    private static let hubCarouselCount = 6

    /// 顶部大卡片的内容：热门列表去掉 AI 作品后，按列表本身的顺序取前几个。
    ///
    /// 上游的做法是从标题最长的十个里随机挑六个；这里改成「当前热门的前几名」。
    /// 同一个作品常有多个版本同时上热门，所以仍然按标题去重，这一点和上游一致。
    static func hubCarousel(_ galleries: [Gallery]) -> [Gallery] {
        Array(
            galleries
                .hubRemovingAIGenerated()
                .removeDuplicates(by: \.trimmedTitle)
                .prefix(hubCarouselCount)
        )
    }
}

// MARK: 「AI 热门」入口

extension HomeSectionsView {
    /// 主页最底部的「AI 热门」入口。点进去是热门页的另一种模式：只显示 AI 作品。
    var hubAIPopularEntry: some View {
        HubAIPopularEntry {
            store.send(.hubAIPopularTapped)
        }
    }
}

/// 占满整行的入口卡片，样式沿用上面「更多」那一排卡片的写法。
/// 它只是一个普通按钮，没有任何左右滑动的手势，不会影响侧滑返回。
private struct HubAIPopularEntry: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "AI 热门")
                        .font(.title2.bold())
                    Text(verbatim: "浏览当前热门里的 AI 生成作品。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 15))
            .tint(.primary)
            .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 20)
        .accessibilityIdentifier("home_ai_popular_entry")
    }
}
