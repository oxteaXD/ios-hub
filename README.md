# Hub

把平时用的几个开源 iOS 应用合并进同一个 App，只占一个安装名额。

免费的 Apple ID 侧载有数量限制，同时装不了几个应用。这个仓库把多个开源应用编进同一个 App：
打开后是一个启动页，点哪个进哪个，随时可以切换。以后想加新的应用，按[新增一个应用](#新增一个应用)做即可。

## 目前包含

| 应用 | 上游 | 固定的版本 | 许可证 |
| --- | --- | --- | --- |
| EhPanda | [EhPanda-Team/EhPanda](https://github.com/EhPanda-Team/EhPanda) | 3.0.0 | MIT |
| Pixiv | [Eslzzyl/Pixiv-SwiftUI](https://github.com/Eslzzyl/Pixiv-SwiftUI) | v0.16.3 | AGPL-3.0 |
| Pica | [fanyuecheng/Pica](https://github.com/fanyuecheng/Pica) | v1.5.0 | MIT |

系统要求：**iOS / iPadOS 27.0 及以上**（取决于 EhPanda 3.0.0）。

### 对 EhPanda 做的定制

这里的 EhPanda 不是原样的上游版本，多了下面这些内容筛选
（实现见 [patches/ehpanda](patches/ehpanda) 和 [bridges/ehpanda](bridges/ehpanda)）：

- **默认不显示真人作品。** Cosplay 和 Asian Porn 两个分类在搜索、全局、关注三套筛选里默认排除，
  筛选里点「重置」也是回到这个状态。想看的话，在筛选里把这两个分类重新打开即可。
  收藏、历史、下载不受影响。
- **主页不显示 AI 作品。** 顶部大卡片、首页、排行榜、热门这四个栏目，连同它们点「查看全部」
  进去的完整列表，都不显示带 `other:ai generated` 标签的画廊。搜索和关注保持原样。
- **顶部大卡片改为热门前几名。** 去掉 AI 作品后，按热门列表本身的顺序取前 6 个；
  上游的做法是从标题最长的 10 个里随机挑 6 个。
- **AI 热门。** 主页最底部有一个入口，里面是热门列表里的 AI 作品，和热门页用的是同一份数据：
  热门页去掉 AI，这里只留 AI。

### 对 Pixiv 做的定制

这里的 Pixiv 也不是原样的上游版本（实现见 [patches/pixiv](patches/pixiv) 和
[PixivPalette.swift](App/Modules/PixivPalette.swift)）：

- **配色固定为 Pixiv 官方配色，没有颜色预设。** 强调色是官方的品牌蓝 `#0096FA`，点亮的心（收藏、关注）
  是官方的收藏红 `#FF4060`，深色和浅色模式下是同一组值，取自 pixiv.net 网页当前使用的样式。
  上游设置里的「主题色」（7 个预设加自定义颜色）和设置向导里的「主题强调色」都去掉了，
  以前保存的主题色选择不再生效；浅色 / 深色模式的选择还在。
- **详情页的「收藏」按钮**没收藏时是和「查看评论」一样的中性灰，收藏后变成收藏红。
  上游是两种状态都跟着主题色走。
- **详情页不能左右滑切换到上一个 / 下一个作品。** 横向滑动交还给系统，右滑就是返回。
  同一个作品有多张图时，在图片上左右滑翻页的功能还在，但图片左侧让出了 44 点宽的一条：
  手指从这一条里开始滑不会翻页，留给右滑返回。

### 对 Pica 做的调整

Pica（哔咔漫画客户端）是 Objective-C 写的 UIKit 应用，功能上没有改动，但为了和另外两个应用待在同一个 App 里，
接入方式上有几处和它单独安装时不一样（实现见 [PicaKit](PicaKit)、[patches/pica](patches/pica) 和
[PicaModule.swift](App/Modules/PicaModule.swift)）：

- **第一次进入 Pica 时才载入。** 它依赖的界面库 QMUIKit 一载入就会改写一大批系统界面方法，而且对整个进程生效。
  所以 Pica 和它的依赖库都做成了动态框架放在安装包里，主程序不链接它们：不打开 Pica，另外两个应用完全不受影响。
  打开过之后，这些改写在这次运行期间一直存在，彻底退出 App 再打开才恢复。
- **没有带友盟的统计和性能监控。** 上游接了友盟的三个 SDK。合并之后它们会和别的应用待在同一个进程里，
  性能监控会连别的应用的网络请求一起采集，登录时还会上报账号，所以换成了什么都不做的空实现。
- **它设的全局外观只对它自己生效。** 上游通过 QMUI 的配置表把导航栏、标签栏、开关的样式设成全局的，
  这里收窄到只对 Pica 自己的界面生效。
- **整屏的横向翻页让出了左侧一条。** 排行榜页和横向阅读模式是整屏的横向翻页，手指从左侧 44 点宽以内向右拖是返回上一级，
  不会翻页（和 Pixiv 多图翻页的效果一样）。竖向拖动、轻点不受影响。
- **固定浅色、iPhone 上只竖屏。** 和上游一致：它的界面没有为深色模式做过适配。宿主在它显示期间把窗口固定成浅色，
  离开后恢复。
- **没有照搬上游关闭网络安全限制（ATS）的设置。** 上游允许明文 HTTP，这是整个 App 级别的设置，合并后会连带放宽
  另外两个应用。它代码里写明的地址全是 HTTPS，所以这里保持系统默认；如果遇到个别图片或链接打不开，原因可能在这里。

### 统一的界面风格

三个应用原本各有各的样子。这里照着系统自带的「图书」把看得见的几处统一了一下，只动样式，不动功能和页面结构：

- **启动页是一排书架。** 大标题、粗体的分区标题、分区之间一条细线；每个应用是一本素色封面的书
  （EhPanda 绿、Pixiv 蓝、Pica 粉），封面上印着应用名，下面是名字和一句说明。
- **作品封面统一成小圆角加一圈淡阴影。** 圆角 5（EhPanda 的封面本来就是这个值），阴影是 16% 的黑色、
  模糊半径 5、向下偏 2。Pixiv 原来是 16 的大圆角卡片和 8 的小说封面，EhPanda 的缩略图格子原来是 15，
  Pica 原来是 4 而且没有阴影。卡片原来的排布和底板没有动。标签、分类这类压着字或只有图标的图片格子只统一了圆角，没有加阴影。
- **分区标题统一成粗体的大字。** EhPanda 的分区标题本来就是这样（粗体的 `title3`），Pixiv 各页的分区标题
  （原来是小一号的 `headline`，详情页里还是灰色的）和 Pica 的分区标题（原来是 15 点的常规体，首页的还是蓝色）都改成了它。

没有统一的部分：字体全部保持系统默认的黑体（图书的标题用的是衬线体，这里没有跟）；强调色各用各的
（EhPanda 绿、Pixiv 官方蓝、Pica 原样）。

这几组数值各有一份：宿主和 Pixiv 用 [HubCoverStyle.swift](App/Hub/HubCoverStyle.swift)，
EhPanda 用 [HubCoverShadow.swift](bridges/ehpanda/AppComponents/HubCoverShadow.swift)，
Pica 用 [PCHubHost.m](PicaKit/Host/PCHubHost.m)，改的时候三处一起改。

## 得到安装包

本仓库不需要 Mac。每次推送到 `main`，GitHub Actions 会在官方的 `xcode-27` 运行器上编译，
产出一个**未签名**的 `Hub.ipa`：

1. 打开仓库的 **Actions** 页面，进入最新一次「构建 IPA」。
2. 在页面底部的 **Artifacts** 里下载 `Hub-ipa`（需要登录 GitHub），解压得到 `Hub.ipa`。
3. 用你平时的签名工具签名并安装。

也可以在 Actions 页面点 **Run workflow** 手动构建。构建失败时，运行页面的摘要里会直接列出报错行，
完整日志在 `build-log` 里；构建成功时摘要里有一份包内容清单。
摘要和日志要登录 GitHub 才看得到；编译报错和界面测试的结果另外发了一份到运行页面的 **Annotations** 里，不登录也能看。

每次构建还会并行跑一遍**模拟器界面测试**（[HubUITests.swift](UITests/HubUITests.swift)）：
在 iOS 模拟器里真正点一遍——从启动页进入各个应用、用悬浮按钮返回和切换、长按悬浮按钮直接切换、
拖动悬浮按钮、启动时直接进入上次使用的应用、收到某个应用的链接时切换过去、Pixiv 在 iPhone 上保持竖屏、
EhPanda 主页的「AI 热门」入口能打开、从屏幕左边缘右滑能返回、Pixiv 设置向导里已经没有「主题强调色」，
以及 Pica 能按需载入并显示登录页、它的提示能显示出来、它载入之后另外两个应用仍然能正常打开。
测试结果和启动页、各应用首次启动页上的文字会写进运行摘要。

启动页还会检查三本书是不是排在同一排、有没有互相压住。

这个测试不登录，只覆盖启动、切换和页面跳转，浏览、下载这些功能测不到，内容筛选对不对也测不到；
封面的圆角和阴影、分区标题的字号这类纯样式的改动，测试只能读到文字和位置，看不到样子，同样测不到；
Pixiv 登录之后才看得到的部分（红心和收藏按钮的颜色、详情页去掉了左右滑切换作品）同样测不到，
Pica 登录之后的全部功能也测不到。
其中「横向翻页的左侧让出一条给右滑返回」是个例外：调试构建里有结构相同的测试页面
（[HubProbe.swift](App/Hub/HubProbe.swift)，安装包里没有；SwiftUI 的翻页和 UIKit 的翻页各一个），
界面测试在它们上面验证让出区域以外照常翻页、从让出区域里右滑不会翻页、从屏幕左边缘右滑能返回。
测试会进入 EhPanda 的主页，所以截图和完整的测试日志都不上传，主页上的文字也不记录（Pica 登录之后的界面同样不记录）：
公开仓库的构建记录和产物谁都能看到。

## 使用

- 打开是启动页，点哪本书的封面就进入哪个应用。
- 进入应用后屏幕右侧有一个半透明的悬浮按钮：**轻点**回到启动页，**长按**直接切到别的应用，
  **按住**可以上下拖动。它只停靠在右边缘，左边缘留给系统的侧滑返回。
  应用弹出面板或全屏页面时它会被盖住，关掉面板就又能用了。
- 启动页上可以打开「启动时直接进入上次使用的应用」。

各应用的数据互相独立，登录状态、设置、下载都和单独安装时一样保存在各自的位置。
但它们是存在这个 App 的沙盒里的：**之前单独安装的 EhPanda / Pixiv / Pica 里的数据不会自动过来**，需要重新登录。

## 目录结构

```
App/                    宿主 App 的源码
  HubApp.swift            唯一的程序入口
  Hub/                    启动页、悬浮按钮、模块切换
  Modules/                各应用的接入层（每个应用一两个文件）
  Resources/              宿主自己的图标和颜色
PicaKit/                Pica 那一侧的胶水层（Objective-C），和 Pica 的源码一起编进 PicaKit.framework
  Host/                   代替它原来的应用代理：承载界面的容器、登录页和主界面的切换
  Stubs/                  友盟统计的空实现
UITests/                宿主壳的界面测试（只在模拟器上跑，不进安装包）
Config/Info.plist       合并了各应用所需条目的 Info.plist
patches/                对上游的成片改动，标准补丁文件，构建时打进上游
bridges/                构建时复制进上游模块的新文件（只新增，不改上游文件）
scripts/
  prepare.py              构建前准备：打补丁、复制新文件、准备标签数据和分类颜色、合并依赖锁定文件
  ci_setup.sh             云端各作业共用的准备步骤：装 XcodeGen、跑 prepare.py、生成工程
  build_ipa.sh            编译并打包成未签名 IPA
  embed_pica_frameworks.sh  构建阶段脚本：把 Pica 的依赖库放进安装包
  annotate.py             把编译报错和测试结果另发一份到运行页面的标注里（不登录也能看到）
  smoke_test.sh           在模拟器里跑界面测试并整理结果
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

**三种接入方式。**

- EhPanda 上游已经拆成「薄壳 App + 本地 Swift 包」。宿主直接链接它的包，
  [EhPandaModule.swift](App/Modules/EhPandaModule.swift) 做的就是上游那个壳做的事。
- Pixiv-SwiftUI 上游是单一 App target，它的图片、文案、标签数据都从主 bundle 里找。
  所以它的源码直接编进宿主的 App target，资源查找和上游完全一样；
  [PixivRootView.swift](App/Modules/PixivRootView.swift) 是照着上游入口写的一份入口视图。
- Pica 上游是 Objective-C 写的单一 App target，依赖靠 CocoaPods，而且它把 CocoaPods 生成的工程和各依赖库的源码
  都提交在仓库里。宿主直接引用那个工程，把 Pica 的源码编成一个动态框架（PicaKit），构建时不需要安装 CocoaPods。
  PicaKit 和依赖库只放进安装包、不被主程序链接，由 [PicaModule.swift](App/Modules/PicaModule.swift) 在第一次进入时载入；
  它原来的应用代理由 [PCHubHost](PicaKit/Host/PCHubHost.m) 代替，界面是 UIKit 的，嵌在宿主的 SwiftUI 界面里。

**应用之间的隔离。** 两个应用跑在同一个进程里，会碰到同一批全局对象。已经处理的有：

| 共用的东西 | 问题 | 处理 |
| --- | --- | --- |
| 窗口的深浅色设置 | 两边都会直接改窗口，互相串 | 宿主在切换时保存、恢复各自的设置 |
| Kingfisher 默认下载器 | Pixiv 会把它的配置整个换掉，冲掉 EhPanda 设的 Cookie 和域名前置 | 补丁：Pixiv 改为只调整代理 |
| EhPanda 的域名前置 | 开启后会接管所有 http/https 请求，Pixiv 的图片请求会被改坏 | 补丁：只接管 E-Hentai 系域名 |
| 强调色 | 全局只有一个 | 全局用 Pixiv 官方的品牌蓝（Pixiv 的界面会回到全局强调色），EhPanda 的在它的根视图上单独指定 |
| 屏幕方向 | Pixiv 在 iPhone 上只支持竖屏 | 应用代理按当前应用返回允许的方向 |
| 版本更新提示 | 两边都拿主 bundle 版本和自己上游比较 | 宿主版本号用日期，永远比上游的大 |
| 偏好设置的键名 | 写进同一个域 | 已核对几个应用之间没有重名 |
| 系统界面方法 | Pica 依赖的 QMUIKit 载入时会改写一大批，对整个进程生效 | Pica 和依赖库按需载入：不打开 Pica 就不会发生 |
| 导航栏、标签栏、开关的全局样式 | Pica 通过 QMUI 的配置表设成全局的 | 补丁：收窄到只对 Pica 自己的界面生效 |
| 场景的深浅色 | Pica 只有浅色界面，它另开的提示、弹窗窗口也要是浅色 | 宿主在它显示期间把整个场景固定成浅色，离开后恢复 |
| 统计 SDK | Pica 带的友盟会采集整个进程的网络请求 | 没有带进来，换成空实现 |

EhPanda 是首次进入时才启动的：在那之前它不会改任何全局设置，也不会发起网络请求。
Pica 更进一步，首次进入时才把代码载入进程。

### 对上游的改动

上游子模块里是原样代码，所有改动都由 [scripts/prepare.py](scripts/prepare.py) 在构建前完成，
改动处都有 `[Hub]` 标记。改动有三种写法：

- **按定位文字替换**（写在 `prepare.py` 的 `PATCHES` 里）：一两行的小改动，
  以及内容会随上游版本变化的地方。定位文字必须在上游文件里恰好出现一次。
- **补丁文件**（`patches/<上游>/*.patch`）：成片的功能改动。
- **新增文件**（`bridges/<上游>/`）：原样复制进上游的模块目录，不碰上游已有的文件。

前两种只要对不上就直接报错，不会悄悄打错地方。

| 上游 | 文件 | 改动 | 写法 |
| --- | --- | --- | --- |
| EhPanda | `AppPackage/Package.swift` | 移除 SwiftLint 依赖和构建插件（下游构建不跑上游的代码规范检查） | 替换 |
| EhPanda | `NetworkingFeature/DFURLProtocol.swift` | 域名前置只接管 E-Hentai 系域名 | 替换 |
| EhPanda | `AppFeature/HubBridge.swift` | 让宿主能把场景阶段变化转发给 EhPanda | 新增 |
| EhPanda | `AppModels`、`NetworkingFeature`、`HomeFeature` 里的 10 个文件 | 内容筛选：默认不显示真人作品、主页不显示 AI 作品、顶部大卡片的取法、「AI 热门」入口 | 补丁文件 |
| EhPanda | `AppModels/HubContentFilters.swift` | 判断 AI 作品、按分类筛选的逻辑 | 新增 |
| EhPanda | `HomeFeature/HubAIPopular.swift` | 顶部大卡片的取法、「AI 热门」入口的界面 | 新增 |
| EhPanda | `GalleryCover.swift`、`GalleryThumbnailCell.swift` | 统一的封面样式：封面垫上淡阴影，缩略图格子的圆角从 15 改成和别处一样的 5 | 补丁文件 |
| EhPanda | `AppComponents/HubCoverShadow.swift` | 封面后面垫的那一圈淡阴影 | 新增 |
| Pixiv-SwiftUI | `App/PixivApp.swift` | 去掉 `@main` | 替换 |
| Pixiv-SwiftUI | `Core/Network/CustomProxyConfiguration.swift` | 调整图片代理时保留下载器的现有配置 | 替换 |
| Pixiv-SwiftUI | `ThemeManager.swift`、设置和向导的外观页、带心形图标的卡片、插画和小说详情的信息区，共 14 个文件 | 官方配色：强调色固定、去掉颜色预设的入口、点亮的心统一用收藏红、「收藏」按钮的配色 | 补丁文件 |
| Pixiv-SwiftUI | `IllustDetailNavigation.swift`、`IllustDetailImageSection.swift` | 去掉详情页左右滑切换作品；多图翻页的左侧让出一条给右滑返回 | 补丁文件 |
| Pixiv-SwiftUI | 各种作品卡片和封面、载入时的占位图形、各页的分区标题，共 27 个文件 | 统一的封面样式（圆角 5 加淡阴影）和统一的分区标题（粗体的 `title3`） | 补丁文件 |
| Pica | `PCLoginController.m`、`PCRequest.m`、`PCNewChatBaseRequest.m`、`PCSettingController.m` | 切换登录页和主界面改为通过宿主的入口 `PCHubHost`（原来是通过它自己的应用代理和窗口） | 补丁文件 |
| Pica | `QMUIConfigurationTemplateDefault.m` | 导航栏、标签栏、工具栏、开关的全局样式收窄到只对 Pica 自己的界面生效 | 补丁文件 |
| Pica | `PCComicRankController.m`、`PCComicPictureController.m` | 排行榜页和阅读页的横向翻页让出左侧一条给右滑返回 | 补丁文件 |
| Pica | 本子列表、排行榜、详情页、下载页的封面，首页的分类格子，首页和详情页的分区标题，共 8 个文件 | 统一的封面样式和统一的分区标题（实现在 `PCHubHost` 里） | 补丁文件 |

Pica 还有两处不是改上游文件、而是在编译时换掉的：上游的程序入口（`main.m`、`AppDelegate`、故事板）不参与编译，
由 [PicaKit/Host](PicaKit/Host) 代替；友盟的三个库不参与编译，上游按原样引用的头文件由 [PicaKit/Stubs](PicaKit/Stubs) 里的空实现提供。

Pixiv 的源码直接编在宿主的 App target 里，所以配合补丁的新代码不需要复制进上游，
直接放在 `App/Modules/` 下：[PixivPalette.swift](App/Modules/PixivPalette.swift)（官方配色的数值）、
[PixivPagerEdgeGuard.swift](App/Modules/PixivPagerEdgeGuard.swift)（翻页左侧让出的那一条）
和 [PixivCoverStyle.swift](App/Modules/PixivCoverStyle.swift)（封面的统一样式）。
上游那份颜色预设的数据（`ThemeColors.swift`）没有改动，只是不再被用到，这样以后跟上游更新时补丁不容易对不上。

构建时还会准备两样上游工程以外的东西：

- **Pixiv 的标签翻译数据** `tags.json`。上游把它放在私有仓库里，脚本从上游对应版本的发行包里取出来；
  取不到就用空数据，标签翻译会回退到 Pixiv 自带的译名。
- **EhPanda 的分类颜色**。EhPanda 的包按名字从主 bundle 里取分类颜色（列表里分类标签的底色），
  这些颜色放在它自己壳工程的资源目录里。那个资源目录不能整个带上（里面的强调色会和 Pixiv 的重名），
  所以脚本只把分类颜色抽出来，做成一个单独的资源目录。

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

`--dry-run` 只检查不改动：补丁还能不能对上、Pixiv 的入口文件有没有变。都通过后，
更新 `upstream/versions.json`，提交子模块指针的变化并推送，云端会重新构建。

如果脚本报某个补丁对不上，说明上游改了那段代码：

- 是 `PATCHES` 里的，对照新代码改 `scripts/prepare.py` 里的定位文字。
- 是补丁文件，在子模块里照着旧补丁把改动重新做一遍，再用
  `git -C upstream/EhPanda diff > patches/ehpanda/<名字>.patch` 重新导出。
  一个上游有多个补丁文件时（比如 Pixiv），在命令末尾加上 `-- <这个补丁涉及的文件>`，各导各的。

本机想看补丁打完的效果可以直接运行 `python3 scripts/prepare.py all`，看完用
`python3 scripts/prepare.py revert` 把子模块恢复原样。

在 Windows 上，git 默认把检出的文件转成 CRLF 换行，而补丁文件是 LF，两者对不上。
第一次使用前先运行一次 `python scripts/prepare.py normalize`，把子模块的工作区换成 LF 换行
（只改子模块的本地配置，不影响仓库内容）。

## 已知限制

- 没有带上 EhPanda 的分享扩展。免费账号下每个扩展都要多占一个应用标识，得不偿失。
- EhPanda 设置里的「更换图标」换的是这个 App 的图标；选「默认」会回到宿主自己的图标。
- 切换应用时只保留数据，界面会重建：Pixiv 会回到首页，两边的滚动位置都不保留。
- 同时开启 EhPanda 的域名前置和 Pixiv 的自定义代理时，两者都要改 Kingfisher 默认下载器的配置，
  后改的一方生效时会保留对方的设置，但这个组合没有专门测试过。
- Pixiv 的 iPad 外接键盘菜单命令没有接入。
- 打开过 Pica 之后，QMUIKit 对系统界面方法的改写在这次运行期间一直存在，可能影响另外两个应用的界面细节
  （界面测试只验证了它们还能正常打开）。遇到异常时彻底退出 App 再打开即可恢复。
- Pica 没有放开明文 HTTP（见上面「对 Pica 做的调整」），个别资源可能因此打不开。
- Pica 在 iPhone 上只有竖屏，界面固定为浅色；它的聊天语音、拍照、相册、面容 ID 这些功能没有在真机上验证过。
- 全局强调色是 Pixiv 的品牌蓝，所以启动页和 EhPanda 里由系统直接弹出的东西（比如提示框的按钮）
  也是这个蓝，而不是系统蓝。EhPanda 自己界面上的强调色不受影响。
- EhPanda 的 AI 作品是靠站点的 `other:ai generated` 标签判断的，没打这个标签的 AI 作品筛不掉。
- EhPanda 的排行榜在站点那边不支持筛选，AI 作品和被排除的分类是拿到数据之后才去掉的，
  所以每一页显示出来的条数会比 50 少，名次也是去掉之后重新排的。
- 「AI 热门」的数量取决于当时热门列表里有多少 AI 作品，不能翻页。

## 许可证

整合后的整体按 [GNU AGPL-3.0](LICENSE) 发布（Pixiv-SwiftUI 是 AGPL-3.0，EhPanda 和 Pica 的 MIT 与之兼容）。
上游项目的版权和许可信息见 [NOTICE.md](NOTICE.md)。

本项目与 E-Hentai、Pixiv、哔咔漫画官方没有任何关联，仅供个人学习研究使用。
