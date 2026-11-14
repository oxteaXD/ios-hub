# Hub

把平时用的几个开源 iOS 应用合并进同一个 App，只占一个安装名额。

免费的 Apple ID 侧载有数量限制，同时装不了几个应用。这个仓库把多个开源应用编进同一个 App：
打开后是一个启动页，点哪个进哪个，随时可以切换。以后想加新的应用，按[新增一个应用](#新增一个应用)做即可。

## 目前包含

| 应用 | 上游 | 固定的版本 | 许可证 |
| --- | --- | --- | --- |
| EhPanda | [EhPanda-Team/EhPanda](https://github.com/EhPanda-Team/EhPanda) | 3.0.0 | MIT |
| Pixiv | [Eslzzyl/Pixiv-SwiftUI](https://github.com/Eslzzyl/Pixiv-SwiftUI) | v0.16.3 | AGPL-3.0 |

系统要求：**iOS / iPadOS 27.0 及以上**（取决于 EhPanda 3.0.0）。

## 得到安装包

本仓库不需要 Mac。每次推送到 `main`，GitHub Actions 会在官方的 `xcode-27` 运行器上编译，
产出一个**未签名**的 `Hub.ipa`：

1. 打开仓库的 **Actions** 页面，进入最新一次「构建 IPA」。
2. 在页面底部的 **Artifacts** 里下载 `Hub-ipa`（需要登录 GitHub），解压得到 `Hub.ipa`。
3. 用你平时的签名工具签名并安装。

也可以在 Actions 页面点 **Run workflow** 手动构建。构建失败时，运行页面的摘要里会直接列出报错行，
完整日志在 `build-log` 里。

## 使用

- 打开是启动页，点卡片进入对应的应用。
- 进入应用后屏幕上有一个半透明的悬浮按钮：**轻点**回到启动页，**长按**直接切到别的应用，
  **按住拖动**可以挪位置。应用弹出面板或全屏页面时它会被盖住，关掉面板就又能用了。
- 启动页上可以打开「启动时直接进入上次使用的应用」。

各应用的数据互相独立，登录状态、设置、下载都和单独安装时一样保存在各自的位置。
但它们是存在这个 App 的沙盒里的：**之前单独安装的 EhPanda / Pixiv 里的数据不会自动过来**，需要重新登录。

## 目录结构

```
App/                    宿主 App 的源码
  HubApp.swift            唯一的程序入口
  Hub/                    启动页、悬浮按钮、模块切换
  Modules/                各应用的接入层（每个应用一两个文件）
  Resources/              宿主自己的图标和颜色
Config/Info.plist       合并了各应用所需条目的 Info.plist
bridges/                构建时复制进上游模块的桥接文件（只新增，不改上游文件）
scripts/
  prepare.py              构建前准备：打补丁、注入桥接文件、准备标签数据、合并依赖锁定文件
  build_ipa.sh            编译并打包成未签名 IPA
  make_icon.py            生成宿主图标（想换图标时才用）
upstream/               上游项目，git 子模块，保持原样
  versions.json           各上游固定的版本
project.yml             XcodeGen 工程描述（Xcode 工程不入库，构建时生成）
.github/workflows/      云端构建流程
```

## 工作原理

**宿主壳。** `HubApp` 是整个 App 唯一的入口。`HubRootView` 没选中应用时显示启动页，选中后只挂载
那一个应用的界面。各应用的数据层（EhPanda 的状态仓库、Pixiv 的各个单例）不随界面卸载而销毁，
所以切回来时登录状态和下载队列都在。界面状态则会重建：Pixiv 会回到首页；EhPanda 的标签页和
导航栈存在它的状态仓库里，按设计能保留，滚动位置不保留。

**两种接入方式。**

- EhPanda 上游已经拆成「薄壳 App + 本地 Swift 包」。宿主直接链接它的包，
  [EhPandaModule.swift](App/Modules/EhPandaModule.swift) 做的就是上游那个壳做的事。
- Pixiv-SwiftUI 上游是单一 App target，它的图片、文案、标签数据都从主 bundle 里找。
  所以它的源码直接编进宿主的 App target，资源查找和上游完全一样；
  [PixivRootView.swift](App/Modules/PixivRootView.swift) 是照着上游入口写的一份入口视图。

**应用之间的隔离。** 两个应用跑在同一个进程里，会碰到同一批全局对象。已经处理的有：

| 共用的东西 | 问题 | 处理 |
| --- | --- | --- |
| 窗口的深浅色设置 | 两边都会直接改窗口，互相串 | 宿主在切换时保存、恢复各自的设置 |
| Kingfisher 默认下载器 | Pixiv 会把它的配置整个换掉，冲掉 EhPanda 设的 Cookie 和域名前置 | 补丁：Pixiv 改为只调整代理 |
| EhPanda 的域名前置 | 开启后会接管所有 http/https 请求，Pixiv 的图片请求会被改坏 | 补丁：只接管 E-Hentai 系域名 |
| 强调色 | 全局只有一个 | 全局沿用 Pixiv 的，EhPanda 的在它的根视图上单独指定 |
| 屏幕方向 | Pixiv 在 iPhone 上只支持竖屏 | 应用代理按当前应用返回允许的方向 |
| 版本更新提示 | 两边都拿主 bundle 版本和自己上游比较 | 宿主版本号用日期，永远比上游的大 |
| 偏好设置的键名 | 写进同一个域 | 已核对两边没有重名 |

EhPanda 是首次进入时才启动的：在那之前它不会改任何全局设置，也不会发起网络请求。

### 对上游的改动

上游子模块里是原样代码，所有改动都由 [scripts/prepare.py](scripts/prepare.py) 在构建前完成，
改动处都有 `[Hub]` 标记。每个补丁的定位文字必须在上游文件里恰好出现一次，否则脚本直接报错，
不会悄悄打错地方。

| 上游 | 文件 | 改动 |
| --- | --- | --- |
| EhPanda | `AppPackage/Package.swift` | 移除 SwiftLint 依赖和构建插件（下游构建不跑上游的代码规范检查） |
| EhPanda | `NetworkingFeature/DFURLProtocol.swift` | 域名前置只接管 E-Hentai 系域名 |
| EhPanda | `AppFeature/HubBridge.swift`（新增） | 让宿主能把场景阶段变化转发给 EhPanda |
| Pixiv-SwiftUI | `App/PixivApp.swift` | 去掉 `@main` |
| Pixiv-SwiftUI | `Core/Network/CustomProxyConfiguration.swift` | 调整图片代理时保留下载器的现有配置 |

另外，Pixiv 上游编译时需要的标签翻译数据 `tags.json` 存在它的私有仓库里。构建时脚本会从它对应版本的
发行包里取出这份数据；取不到就用空数据，标签翻译会回退到 Pixiv 自带的译名。

## 新增一个应用

1. 把上游加为子模块：`git submodule add <地址> upstream/<名字>`，并在 `upstream/versions.json` 里记下版本。
2. 在 `project.yml` 里接入它的代码。上游是 Swift 包的，加到 `packages` 并在 `dependencies` 里链接；
   上游是单一 App target 的，需要给它建一个独立的 framework target，避免和已有代码重名。
3. 在 `App/Modules/` 下写一个接入文件，构造一个 `HubModule`（标题、图标、根视图、启动逻辑），
   登记到 [HubModule.swift](App/Hub/HubModule.swift) 的 `HubModuleRegistry.all`。
4. 上游有 `@main` 的要去掉，在 `scripts/prepare.py` 的 `PATCHES` 里加一条。
5. 把它需要的 Info.plist 条目（权限说明、URL scheme、后台模式等）合并进 `Config/Info.plist`。
6. 对照上面「应用之间的隔离」那张表，检查它会不会动同一批全局对象。

## 更新上游版本

```bash
git -C upstream/EhPanda fetch --tags && git -C upstream/EhPanda checkout <新版本>
python3 scripts/prepare.py all --dry-run
```

`--dry-run` 只检查不改动：补丁还能不能准确定位、Pixiv 的入口文件有没有变。都通过后，
更新 `upstream/versions.json`，提交子模块指针的变化并推送，云端会重新构建。
如果脚本报某个补丁定位不到，说明上游改了那段代码，需要对照新代码更新 `scripts/prepare.py`。

本机想看补丁打完的效果可以直接运行 `python3 scripts/prepare.py all`，看完用
`python3 scripts/prepare.py revert` 把子模块恢复原样。

## 已知限制

- 没有带上 EhPanda 的分享扩展。免费账号下每个扩展都要多占一个应用标识，得不偿失。
- EhPanda 设置里的「更换图标」换的是这个 App 的图标；选「默认」会回到宿主自己的图标。
- 切换应用时只保留数据，界面会重建：Pixiv 会回到首页，两边的滚动位置都不保留。
- 同时开启 EhPanda 的域名前置和 Pixiv 的自定义代理时，两者都要改 Kingfisher 默认下载器的配置，
  后改的一方生效时会保留对方的设置，但这个组合没有专门测试过。
- Pixiv 的 iPad 外接键盘菜单命令没有接入。

## 许可证

整合后的整体按 [GNU AGPL-3.0](LICENSE) 发布（Pixiv-SwiftUI 是 AGPL-3.0，EhPanda 的 MIT 与之兼容）。
上游项目的版权和许可信息见 [NOTICE.md](NOTICE.md)。

本项目与 E-Hentai、Pixiv 官方没有任何关联，仅供个人学习研究使用。
