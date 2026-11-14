// 这个文件不属于 EhPanda 上游。
// 它由宿主工程的 scripts/prepare.py 在构建前复制进 AppModels 模块，集中放「AI 作品」和
// 「按分类筛选」这两件事的判断逻辑，上游文件里只留调用。

// MARK: AI 作品

extension Gallery {
    /// 站点给 AI 生成的作品打的标签是 `other:ai generated`。
    private static let hubAIGeneratedNamespace = "other"
    private static let hubAIGeneratedText = "ai generated"

    /// 这个画廊是不是 AI 生成的作品。
    public var hubIsAIGenerated: Bool {
        tags.contains { tag in
            tag.rawNamespace.lowercased() == Self.hubAIGeneratedNamespace
                && tag.contents.contains { $0.text.lowercased() == Self.hubAIGeneratedText }
        }
    }

    /// 如果元数据说这是 AI 作品，而列表项的标签里没有 AI 标签，就把它补上。
    ///
    /// 列表页面只显示每个画廊的一部分标签，AI 标签经常不在其中（实测热门列表里约十分之一看不到）；
    /// 元数据接口返回的才是完整标签。补上之后，`hubIsAIGenerated` 在任何地方都可靠，
    /// 列表里也能看到这个标签。
    public mutating func hubAdoptAIGeneratedTag(from metadata: Gallery) {
        guard metadata.hubIsAIGenerated, !hubIsAIGenerated else { return }
        let content = GalleryTag.Content(
            rawNamespace: Self.hubAIGeneratedNamespace,
            text: Self.hubAIGeneratedText,
            isVotedUp: false,
            isVotedDown: false
        )
        if let index = tags.firstIndex(where: { $0.rawNamespace.lowercased() == Self.hubAIGeneratedNamespace }) {
            tags[index] = GalleryTag(
                rawNamespace: tags[index].rawNamespace,
                contents: tags[index].contents + [content]
            )
        } else {
            tags.append(GalleryTag(rawNamespace: Self.hubAIGeneratedNamespace, contents: [content]))
        }
    }
}

extension URLUtil {
    /// 站点搜索里「排除 AI 标签」的写法，加在首页的请求上。
    static let hubAIGeneratedExclusion = "-other:\"ai generated$\""
}

// MARK: 按分类筛选

extension Filter {
    /// 这个筛选有没有把某个分类排除掉。
    ///
    /// 筛选里各分类的开关为 true 表示排除，和上游拼进请求地址的 `f_cats` 参数含义一致。
    public func hubExcludes(_ category: AppModels.Category) -> Bool {
        switch category {
        case .doujinshi: return doujinshi
        case .manga: return manga
        case .artistCG: return artistCG
        case .gameCG: return gameCG
        case .western: return western
        case .nonH: return nonH
        case .imageSet: return imageSet
        case .cosplay: return cosplay
        case .asianPorn: return asianPorn
        case .misc: return misc
        case .private: return false
        }
    }

    /// 分类筛选是否真的起作用。和上游的规则保持一致：一个都没排除，或者全部排除，都等于不筛选。
    var hubHasEffectiveCategoryExclusion: Bool {
        let filterable = AppModels.Category.allFiltersCases
        let excludedCount = filterable.filter(hubExcludes).count
        return excludedCount > 0 && excludedCount < filterable.count
    }
}

extension Array where Element == Gallery {
    /// 去掉 AI 生成的作品。
    public func hubRemovingAIGenerated() -> [Gallery] {
        filter { !$0.hubIsAIGenerated }
    }

    /// 只保留 AI 生成的作品。
    public func hubKeepingAIGenerated() -> [Gallery] {
        filter { $0.hubIsAIGenerated }
    }

    /// 去掉筛选里被排除的分类。
    ///
    /// 首页、热门、搜索的分类筛选由站点在服务端完成；排行榜的接口不支持筛选，只能拿到之后在这里筛。
    public func hubRemovingExcludedCategories(_ criteria: Filter) -> [Gallery] {
        guard criteria.hubHasEffectiveCategoryExclusion else { return self }
        return filter { !criteria.hubExcludes($0.category) }
    }
}
