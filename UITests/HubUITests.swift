import UIKit
import XCTest

/// 宿主壳的界面测试：在模拟器里真正点一遍——从启动页进入各个应用，用悬浮按钮返回和切换。
///
/// 每到一个界面，就把屏幕上的文字打印出来（每行以 `HUBUI|` 开头），`scripts/smoke_test.sh`
/// 会把这些行收集进测试结果。这样不看截图也能知道每个界面实际显示了什么。
///
/// 测试不登录、不联网，只覆盖宿主自己的逻辑：启动、挂载模块、切换。
final class HubUITests: XCTestCase {
    /// 界面语言固定成简体中文，顺便检验各模块的中文文案能不能正常显示。
    private let languageArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 启动页 → EhPanda → 启动页 → Pixiv → 启动页 → 再进 EhPanda。
    @MainActor
    func testSwitchingBetweenModules() throws {
        let app = makeApp(["-hub.autoEnterLastModule", "NO"])
        app.launch()

        let ehpandaCard = element("hub.module.ehpanda", in: app)
        let pixivCard = element("hub.module.pixiv", in: app)
        let switcher = element("hub.switcher", in: app)

        XCTAssertTrue(ehpandaCard.waitForExistence(timeout: 60), "启动页上没有出现 EhPanda 的那本书")
        XCTAssertTrue(pixivCard.exists, "启动页上没有出现 Pixiv 的那本书")
        XCTAssertFalse(switcher.exists, "启动页上不应该有悬浮按钮")
        checkLauncherShelf(in: app)
        report("启动页", app)

        ehpandaCard.tap()
        XCTAssertTrue(switcher.waitForExistence(timeout: 60), "进入 EhPanda 后没有出现悬浮按钮")
        XCTAssertEqual(switcher.value as? String, "EhPanda")
        settle(8)
        report("EhPanda", app)

        switcher.tap()
        XCTAssertTrue(pixivCard.waitForExistence(timeout: 30), "轻点悬浮按钮后没有回到启动页")
        XCTAssertFalse(switcher.exists, "回到启动页后悬浮按钮应该消失")

        pixivCard.tap()
        XCTAssertTrue(switcher.waitForExistence(timeout: 60), "进入 Pixiv 后没有出现悬浮按钮")
        XCTAssertEqual(switcher.value as? String, "Pixiv")
        settle(10)
        report("Pixiv", app)

        switcher.tap()
        XCTAssertTrue(ehpandaCard.waitForExistence(timeout: 30), "从 Pixiv 轻点悬浮按钮后没有回到启动页")

        ehpandaCard.tap()
        XCTAssertTrue(switcher.waitForExistence(timeout: 60), "第二次进入 EhPanda 后没有出现悬浮按钮")
        XCTAssertEqual(switcher.value as? String, "EhPanda")
        settle(5)
        report("第二次进入 EhPanda", app)

        XCTAssertEqual(app.state, .runningForeground, "测试结束时 App 应该仍在前台运行")
    }

    /// 开启「启动时直接进入上次使用的应用」后，启动应当直接停在那个应用里。
    @MainActor
    func testEnteringLastModuleOnLaunch() throws {
        let app = makeApp(["-hub.autoEnterLastModule", "YES", "-hub.lastModule", "pixiv"])
        app.launch()

        let switcher = element("hub.switcher", in: app)
        XCTAssertTrue(switcher.waitForExistence(timeout: 60), "没有直接进入上次使用的应用")
        XCTAssertEqual(switcher.value as? String, "Pixiv")
        XCTAssertFalse(element("hub.module.pixiv", in: app).exists, "不应该停在启动页")
        settle(8)
        report("启动时直接进入 Pixiv", app)
    }

    /// 停在 Pixiv 时收到 EhPanda 的链接，宿主应当切换到 EhPanda。
    @MainActor
    func testOpeningModuleLinkSwitchesToThatModule() throws {
        let app = makeApp(["-hub.autoEnterLastModule", "YES", "-hub.lastModule", "pixiv"])
        app.launch()

        let switcher = element("hub.switcher", in: app)
        XCTAssertTrue(switcher.waitForExistence(timeout: 60), "没有直接进入上次使用的应用")
        XCTAssertEqual(switcher.value as? String, "Pixiv")
        settle(5)

        let link = try XCTUnwrap(URL(string: "ehpanda://hub-smoke-test"))
        app.open(link)

        expectation(for: NSPredicate(format: "value == %@", "EhPanda"), evaluatedWith: switcher)
        waitForExpectations(timeout: 30)
        settle(5)
        report("收到 EhPanda 链接后", app)

        XCTAssertEqual(app.state, .runningForeground, "测试结束时 App 应该仍在前台运行")
    }

    /// 长按悬浮按钮弹出菜单，可以不经过启动页直接切到另一个应用。
    @MainActor
    func testLongPressingSwitcherOffersOtherModules() throws {
        let app = makeApp(["-hub.autoEnterLastModule", "YES", "-hub.lastModule", "ehpanda"])
        app.launch()

        let switcher = element("hub.switcher", in: app)
        XCTAssertTrue(switcher.waitForExistence(timeout: 60), "没有直接进入上次使用的应用")
        XCTAssertEqual(switcher.value as? String, "EhPanda")
        settle(3)

        switcher.press(forDuration: 1.5)
        let pixivItem = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Pixiv"))
            .firstMatch
        XCTAssertTrue(pixivItem.waitForExistence(timeout: 10), "长按悬浮按钮后，菜单里没有出现 Pixiv")
        report("长按悬浮按钮的菜单", app)

        pixivItem.tap()
        XCTAssertTrue(
            waitUntil(timeout: 30) { (switcher.value as? String) == "Pixiv" },
            "在菜单里选 Pixiv 后没有切换过去"
        )
        XCTAssertEqual(app.state, .runningForeground, "测试结束时 App 应该仍在前台运行")
    }

    /// 悬浮按钮可以上下拖动，但松手后总是回到右边缘：左边缘要留给侧滑返回。
    @MainActor
    func testDraggingSwitcherKeepsItOnTheRightEdge() throws {
        let app = makeApp(["-hub.autoEnterLastModule", "YES", "-hub.lastModule", "ehpanda"])
        app.launch()

        let switcher = element("hub.switcher", in: app)
        XCTAssertTrue(switcher.waitForExistence(timeout: 60), "没有直接进入上次使用的应用")
        settle(3)
        report("直接进入 EhPanda", app)

        let before = switcher.frame
        XCTAssertGreaterThan(before.midX, app.frame.midX, "悬浮按钮应该停在屏幕右侧")

        // 往屏幕左侧拖，同时换一个高度：之前在下半屏就拖到上面，反之拖到下面。
        let targetY: CGFloat = before.midY > app.frame.midY ? 0.25 : 0.75
        let start = switcher.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: targetY))
        start.press(forDuration: 0.1, thenDragTo: end)
        settle(2)

        let after = switcher.frame
        print("HUBUI|拖动悬浮按钮|拖动前 \(describe(before))，拖动后 \(describe(after))，屏幕 \(describe(app.frame))")
        XCTAssertEqual(after.midX, before.midX, accuracy: 2, "拖到左侧松手后，悬浮按钮应该回到右边缘")
        XCTAssertGreaterThan(abs(after.midY - before.midY), 100, "悬浮按钮的高度应该跟着拖动改变")
        XCTAssertEqual(switcher.value as? String, "EhPanda", "拖动不应该触发切换")
    }

    /// EhPanda 主页最底部有「AI 热门」入口，点进去是列表页，从屏幕左边缘右滑能返回。
    ///
    /// 这个测试会走过成年确认页进入主页。主页的内容不截图也不打印（见 `report`），
    /// 这里只关心入口在不在、页面能不能打开、侧滑返回管不管用，这三件事都不依赖联网。
    @MainActor
    func testEhPandaAIPopularEntryAndEdgeSwipeBack() throws {
        let app = makeApp(["-hub.autoEnterLastModule", "YES", "-hub.lastModule", "ehpanda"])
        app.launch()

        checkEhPandaAIPopularAndEdgeSwipeBack(in: app, group: "AI 热门入口")

        XCTAssertEqual(app.state, .runningForeground, "测试结束时 App 应该仍在前台运行")
    }

    /// Pixiv 在 iPhone 上只允许竖屏；启动页和 EhPanda 可以横屏。
    @MainActor
    func testOrientationFollowsActiveModule() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "只在 iPhone 上检查屏幕方向的限制")

        let app = makeApp(["-hub.autoEnterLastModule", "YES", "-hub.lastModule", "pixiv"])
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }

        let switcher = element("hub.switcher", in: app)
        XCTAssertTrue(switcher.waitForExistence(timeout: 60), "没有直接进入上次使用的应用")
        XCTAssertEqual(switcher.value as? String, "Pixiv")
        settle(3)

        XCUIDevice.shared.orientation = .landscapeLeft
        settle(4)
        print("HUBUI|屏幕方向|Pixiv 里把设备横过来：界面 \(describe(app.frame))")
        XCTAssertLessThan(app.frame.width, app.frame.height, "在 Pixiv 里把设备横过来，界面应该保持竖屏")

        switcher.tap()
        let pixivCard = element("hub.module.pixiv", in: app)
        XCTAssertTrue(pixivCard.waitForExistence(timeout: 30), "轻点悬浮按钮后没有回到启动页")
        let launcherRotated = waitUntil(timeout: 15) { app.frame.width > app.frame.height }
        print("HUBUI|屏幕方向|回到启动页（设备仍然横着）：界面 \(describe(app.frame))")
        XCTAssertTrue(launcherRotated, "回到启动页后，界面应该跟着设备转成横屏")

        pixivCard.tap()
        XCTAssertTrue(switcher.waitForExistence(timeout: 60), "从横屏的启动页进入 Pixiv 后没有出现悬浮按钮")
        let pixivRotatedBack = waitUntil(timeout: 15) { app.frame.width < app.frame.height }
        print("HUBUI|屏幕方向|再次进入 Pixiv（设备仍然横着）：界面 \(describe(app.frame))")
        XCTAssertTrue(pixivRotatedBack, "再次进入 Pixiv 后，界面应该转回竖屏")
    }

    /// UIKit 写的整屏横向翻页（Pica 的排行榜页和横向阅读）同样让出了左侧一条，用的是 `HubEdgeBackGuard`。
    /// 这些页面要登录才进得去，所以同样是在调试构建里结构相同的测试页面上验证。
    @MainActor
    func testEdgeBackGuardOnUIKitPager() throws {
        // 先看不装让出区域的对照页面：确认测试页面本身能翻页，并记下系统原本的行为。
        let bare = makeApp(["-hub.autoEnterLastModule", "NO", "-hub.probe", "uikitPagerWithoutGuard"])
        bare.launch()
        let barePage = element("probe.page", in: bare)
        XCTAssertTrue(barePage.waitForExistence(timeout: 60), "没有打开 UIKit 的翻页测试页面（对照）")
        settle(2)
        XCTAssertTrue(
            dragAcrossPager(in: bare, from: 0.8, to: 0.15, until: barePage, shows: "2"),
            "对照页面：从页面中间向左滑，没有翻到第 2 页"
        )
        for pointsFromLeft in [CGFloat(30), CGFloat(3)] {
            guard barePage.exists else { break }
            if barePage.label != "2" {
                guard dragAcrossPager(in: bare, from: 0.8, to: 0.15, until: barePage, shows: "2") else { break }
            }
            dragRightAcrossPager(in: bare, pointsFromLeft: pointsFromLeft)
            settle(3)
            let outcome: String
            if !barePage.exists {
                outcome = "返回了上一级"
            } else if barePage.label == "1" {
                outcome = "翻回了第 1 页"
            } else {
                outcome = "没有翻页，也没有返回"
            }
            print("HUBUI|UIKit 翻页左侧让出区域|对照（不装让出区域）从距左边缘 \(Int(pointsFromLeft)) 点处右滑：\(outcome)")
        }
        bare.terminate()
        settle(3)

        // 再看装了让出区域的页面。
        let app = makeApp(["-hub.autoEnterLastModule", "NO", "-hub.probe", "uikitPagerEdgeGuard"])
        app.launch()

        let page = element("probe.page", in: app)
        let taps = element("probe.imageTaps", in: app)
        let middle = element("probe.middle", in: app)
        let root = element("probe.root", in: app)
        XCTAssertTrue(page.waitForExistence(timeout: 60), "没有打开 UIKit 的翻页测试页面")
        // 页面刚出来时界面还没稳下来，模拟器卡的时候这时去读内容会超时，所以先等一等。
        settle(3)
        XCTAssertEqual(page.label, "1")

        // 在让出区域以外，翻页照常。
        XCTAssertTrue(
            dragAcrossPager(in: app, from: 0.8, to: 0.15, until: page, shows: "2"),
            "装了让出区域之后，从页面中间向左滑，没有翻到第 2 页"
        )
        XCTAssertTrue(
            dragAcrossPager(in: app, from: 0.4, to: 0.95, until: page, shows: "1"),
            "装了让出区域之后，从页面中间向右滑，没有翻回第 1 页"
        )
        XCTAssertTrue(
            dragAcrossPager(in: app, from: 0.8, to: 0.15, until: page, shows: "2"),
            "装了让出区域之后，第二次向左滑，没有翻到第 2 页"
        )

        // 轻点不受影响：让出区域里的轻点照样落在页面上。
        pagerPoint(in: app, pointsFromLeft: 22).tap()
        XCTAssertTrue(waitUntil(timeout: 5) { taps.label == "1" }, "轻点让出区域，页面没有收到这次点击")
        pagerPoint(in: app, pointsFromLeft: 200).tap()
        XCTAssertTrue(waitUntil(timeout: 5) { taps.label == "2" }, "轻点让出区域以外，页面没有收到这次点击")
        XCTAssertEqual(page.label, "2", "轻点不应该翻页")

        // 从让出区域里向左滑：既不翻页，也不返回。
        let stripPoint = pagerPoint(in: app, pointsFromLeft: 30)
        stripPoint.press(forDuration: 0.05, thenDragTo: pagerPoint(in: app, pointsFromLeft: 2))
        settle(2)
        XCTAssertTrue(page.exists, "从让出区域里向左滑，不应该返回")
        XCTAssertEqual(page.label, "2", "从让出区域里向左滑，不应该翻页")

        // 从让出区域里向右滑：返回上一级，而且恰好一级（停在中间页，不是首页）。
        dragRightAcrossPager(in: app, pointsFromLeft: 30)
        XCTAssertTrue(waitUntil(timeout: 10) { !page.exists }, "从左侧让出的区域向右滑，没有返回上一级")
        XCTAssertTrue(middle.waitForExistence(timeout: 10), "从让出区域右滑之后，没有停在上一级页面")
        XCTAssertFalse(root.exists, "从让出区域右滑一次，多返回了一级")
        print("HUBUI|UIKit 翻页左侧让出区域|从让出区域里（距左边缘 30 点）右滑：返回了上一级，恰好一级")
        app.terminate()
        settle(3)

        // 贴着屏幕最左边缘向右滑：系统自己的右滑返回照常，同样恰好返回一级（宿主加的返回不会再叠一次）。
        let edgeApp = makeApp(["-hub.autoEnterLastModule", "NO", "-hub.probe", "uikitPagerEdgeGuard"])
        edgeApp.launch()
        let edgePage = element("probe.page", in: edgeApp)
        XCTAssertTrue(edgePage.waitForExistence(timeout: 60), "第二次没有打开 UIKit 的翻页测试页面")
        settle(2)
        dragRightAcrossPager(in: edgeApp, pointsFromLeft: 3)
        XCTAssertTrue(waitUntil(timeout: 10) { !edgePage.exists }, "在翻页区域里从屏幕左边缘右滑，没有返回上一级")
        XCTAssertTrue(element("probe.middle", in: edgeApp).waitForExistence(timeout: 10), "从屏幕左边缘右滑之后，没有停在上一级页面")
        settle(2)
        XCTAssertFalse(element("probe.root", in: edgeApp).exists, "从屏幕左边缘右滑一次，多返回了一级")
        print("HUBUI|UIKit 翻页左侧让出区域|从屏幕左边缘（距左边缘 3 点）右滑：返回了上一级，恰好一级")
    }

    /// Pica 的代码和依赖库是进入它的时候才载入的。这里从启动页进入 Pica，确认它的登录页出来了、
    /// 它的提示能显示在宿主的窗口上；再回到启动页进入另外两个应用，确认 Pica 载入之后它们仍然能正常打开
    /// （Pica 依赖的 QMUIKit 载入后会改写一批系统界面方法，对整个进程生效）。
    @MainActor
    func testPicaLoadsOnDemandAndOtherModulesStillWork() throws {
        let app = makeApp(["-hub.autoEnterLastModule", "NO"])
        app.launch()

        let picaCard = element("hub.module.pica", in: app)
        let ehpandaCard = element("hub.module.ehpanda", in: app)
        let pixivCard = element("hub.module.pixiv", in: app)
        let switcher = element("hub.switcher", in: app)
        XCTAssertTrue(picaCard.waitForExistence(timeout: 60), "启动页上没有出现 Pica 的那本书")

        picaCard.tap()
        XCTAssertTrue(switcher.waitForExistence(timeout: 60), "进入 Pica 后没有出现悬浮按钮")
        XCTAssertEqual(switcher.value as? String, "Pica")

        // 没登录时显示的是登录页；载入失败的话宿主会把原因显示出来。
        let loginButton = app.buttons["登录"]
        let failure = element("pica.loadFailure", in: app)
        XCTAssertTrue(
            waitUntil(timeout: 60) { loginButton.exists || failure.exists },
            "进入 Pica 后既没有出现登录页，也没有出现载入失败的说明"
        )
        if failure.exists {
            report("Pica 载入失败", app)
            XCTFail("Pica 没有载入成功，原因见测试结果里的「Pica 载入失败」")
            return
        }
        XCTAssertTrue(app.buttons["注册"].exists, "Pica 的登录页上没有「注册」按钮")
        settle(2)
        report("Pica 登录页", app)

        let diagnostics = element("pica.diagnostics", in: app)
        if waitUntil(timeout: 10, { diagnostics.exists && !diagnostics.label.isEmpty }) {
            print("HUBUI|Pica 登录页|自检：\(diagnostics.label)")
            XCTAssertFalse(diagnostics.label.contains("没有找到"), "Pica 用的界面库没有找到宿主的主窗口，它的提示和弹窗会显示不出来")
        } else {
            print("HUBUI|Pica 登录页|没有读到自检信息")
        }

        // 不填账号密码直接点登录，Pica 会弹出一条提示。提示是它的界面库加在主窗口上的，能出来说明这条路是通的。
        // 提示只显示一两秒，测试来不及直接看到，所以看自检信息：那一侧会把见到过的提示记下来。
        loginButton.tap()
        let tipSeen = waitUntil(timeout: 20) { diagnostics.exists && diagnostics.label.contains("请输入账号或者密码") }
        if !tipSeen {
            print("HUBUI|Pica 登录页|点「登录」之后的自检：\(diagnostics.exists ? diagnostics.label : "读不到")")
        }
        XCTAssertTrue(tipSeen, "点「登录」后没有出现 Pica 的提示")
        print("HUBUI|Pica 登录页|不填账号密码点「登录」：出现了提示「请输入账号或者密码」")
        settle(3)

        // 回到启动页，依次进入另外两个应用：Pica 已经载入，它们应当照常打开。
        switcher.tap()
        XCTAssertTrue(ehpandaCard.waitForExistence(timeout: 30), "从 Pica 轻点悬浮按钮后没有回到启动页")

        ehpandaCard.tap()
        XCTAssertTrue(switcher.waitForExistence(timeout: 60), "Pica 载入之后进入 EhPanda，没有出现悬浮按钮")
        XCTAssertEqual(switcher.value as? String, "EhPanda")
        // QMUIKit 载入后会接管进程里所有导航控制器的返回手势代理，所以在这里把 EhPanda 的侧滑返回再验一遍。
        checkEhPandaAIPopularAndEdgeSwipeBack(in: app, group: "Pica 载入之后的 EhPanda")

        switcher.tap()
        XCTAssertTrue(pixivCard.waitForExistence(timeout: 30), "从 EhPanda 轻点悬浮按钮后没有回到启动页")
        pixivCard.tap()
        XCTAssertTrue(switcher.waitForExistence(timeout: 60), "Pica 载入之后进入 Pixiv，没有出现悬浮按钮")
        XCTAssertEqual(switcher.value as? String, "Pixiv")
        XCTAssertTrue(app.buttons["开始设置"].waitForExistence(timeout: 60), "Pica 载入之后进入 Pixiv，没有出现它的设置向导")
        print("HUBUI|Pica 载入之后|Pixiv 正常打开")

        // 再回到 Pica：界面还是原来那一个，不会重新载入。
        switcher.tap()
        XCTAssertTrue(picaCard.waitForExistence(timeout: 30), "从 Pixiv 轻点悬浮按钮后没有回到启动页")
        picaCard.tap()
        XCTAssertTrue(loginButton.waitForExistence(timeout: 30), "第二次进入 Pica 没有出现登录页")
        print("HUBUI|Pica 载入之后|第二次进入 Pica：登录页还在")

        XCTAssertEqual(app.state, .runningForeground, "测试结束时 App 应该仍在前台运行")
    }

    /// Pica 的上游代码里有二十多处跳转是「先问界面库现在屏幕上是哪个页面，再让那个页面所在的导航栈去跳」：
    /// 排行榜、收藏、历史里点一本漫画，详情页里点某一话、标签、评论……界面库原来的找法在宿主里找不到
    /// Pica 的页面，这些点击就没有反应。宿主把找法换掉了（`PCHubHost` 的 redirectVisibleViewControllerLookup）。
    ///
    /// 那些页面都要登录才进得去，这里用登录页和注册页验证同一件事：界面库找到的是 Pica 自己的页面。
    /// 注册页是弹出来的、装在导航栈里的页面；找到了它，并且它带着导航栈，
    /// 说明「弹出的页面 → 导航栈 → 栈顶的页面」这条路在宿主里是通的，那些跳转靠的就是这条路。
    ///
    /// 注册页只打开看一眼就关掉，不填也不提交。它弹着的时候测试读不到底下的自检信息，
    /// 所以让 Pica 那一侧把找到过的页面按先后记下来，关掉之后再看。
    @MainActor
    func testPicaFindsItsOwnPagesInsideHub() throws {
        let app = makeApp(["-hub.autoEnterLastModule", "NO"])
        app.launch()

        let picaCard = element("hub.module.pica", in: app)
        XCTAssertTrue(picaCard.waitForExistence(timeout: 60), "启动页上没有出现 Pica 的那本书")
        picaCard.tap()

        let loginButton = app.buttons["登录"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 60), "进入 Pica 后没有出现登录页")

        let diagnostics = element("pica.diagnostics", in: app)
        let loginPage = "PCLoginController（不在导航栈里）"
        let registerPage = "PCRegistController（在导航栈里）"
        // 自检信息里是「……找到的当前页面依次是：甲 → 乙 → 丙；见到过的最近一条提示：……」，最后一个就是现在的页面。
        func isCurrentPage(_ page: String) -> Bool {
            diagnostics.exists && diagnostics.label.contains("\(page)；见到过的最近一条提示")
        }
        let onLogin = waitUntil(timeout: 20) { isCurrentPage(loginPage) }
        print("HUBUI|Pica 找当前页面|登录页上的自检：\(diagnostics.exists ? diagnostics.label : "读不到")")
        XCTAssertTrue(onLogin, "在登录页上，Pica 的界面库找到的当前页面不是登录页")
        XCTAssertTrue(diagnostics.label.contains("换过找当前页面的办法：是"), "宿主没有换掉 Pica 的界面库找当前页面的办法")

        app.buttons["注册"].tap()
        let cancel = app.buttons["取消"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 20), "点「注册」后没有弹出注册页")
        // 自检信息每 0.3 秒取一次，留够时间让它记下弹出来的这一页。
        settle(3)
        cancel.tap()

        let backOnLogin = waitUntil(timeout: 20) {
            isCurrentPage(loginPage) && diagnostics.label.contains(registerPage)
        }
        print("HUBUI|Pica 找当前页面|打开再关掉注册页之后的自检：\(diagnostics.exists ? diagnostics.label : "读不到")")
        XCTAssertTrue(
            backOnLogin,
            "注册页弹着的时候，Pica 的界面库没有找到它或者它所在的导航栈；或者关掉之后没有回到登录页"
        )
        print("HUBUI|Pica 找当前页面|登录页 → 弹出的注册页（带导航栈）→ 登录页：都找对了")

        XCTAssertEqual(app.state, .runningForeground, "测试结束时 App 应该仍在前台运行")
    }

    /// EhPanda 的列表里，已收藏的画廊封面上垂着一条黄色书签。
    ///
    /// 收藏状态只有登录之后的列表页里才有，所以这里用调试构建里的测试页面（`HubProbe`）：
    /// 先拿一小段照着站点列表页写的页面过一遍解析，确认收藏标记被记了下来；
    /// 再摆出几个假画廊（行样式和网格样式各两个，一个已收藏、一个没有），确认书签只出现在已收藏的封面上、
    /// 关掉书签的那一片里不出现（收藏夹页就是这样）、收藏状态变了之后书签跟着换。
    /// 书签长什么样测试看不到，只能确认它在不在、在哪里。
    @MainActor
    func testEhPandaFavoriteRibbonFollowsFavoriteState() throws {
        let app = makeApp(["-hub.autoEnterLastModule", "NO", "-hub.probe", "ehFavoriteMark"])
        app.launch()

        let selfCheck = element("probe.favorite.selfCheck", in: app)
        let state = element("probe.favorite.state", in: app)
        XCTAssertTrue(
            waitUntil(timeout: 90) { state.exists && state.label == "初始" },
            "没有打开收藏书签的测试页面，或者它没有准备好"
        )
        print("HUBUI|EhPanda 收藏书签|\(selfCheck.exists ? selfCheck.label : "读不到自检结果")")
        XCTAssertTrue(selfCheck.label.contains("记上了=是"), "解析列表页时，带收藏标记的那一行没有被记成已收藏")
        XCTAssertTrue(selfCheck.label.contains("去掉了=是"), "解析列表页时，不带收藏标记的那一行没有被记成没收藏")

        func ribbon(_ gid: String) -> XCUIElement {
            element("hub.favorite.\(gid)", in: app)
        }

        XCTAssertTrue(waitUntil(timeout: 15) { ribbon("9000001").exists }, "行样式里已收藏的画廊，封面上没有书签")
        XCTAssertFalse(ribbon("9000002").exists, "行样式里没收藏的画廊，封面上不应该有书签")
        XCTAssertTrue(ribbon("9000003").exists, "网格样式里已收藏的画廊，封面上没有书签")
        XCTAssertFalse(ribbon("9000004").exists, "网格样式里没收藏的画廊，封面上不应该有书签")
        XCTAssertFalse(ribbon("9000005").exists, "关掉书签的那一片里，已收藏的画廊也不应该有书签")
        print(
            "HUBUI|EhPanda 收藏书签|书签的位置：行样式 \(describe(ribbon("9000001").frame))；"
                + "网格样式 \(describe(ribbon("9000003").frame))；屏幕 \(describe(app.frame))"
        )
        print("HUBUI|EhPanda 收藏书签|已收藏的有书签，没收藏的没有，关掉书签的那一片里没有")

        // 对调前两个画廊的收藏状态：书签应当从甲换到乙上（在详情页收藏、取消收藏之后，列表靠的就是这个）。
        element("probe.favorite.swap", in: app).tap()
        let swapped = waitUntil(timeout: 15) {
            state.label == "已对调" && ribbon("9000002").exists && !ribbon("9000001").exists
        }
        XCTAssertTrue(swapped, "收藏状态对调之后，书签没有跟着换到另一个画廊上")
        print("HUBUI|EhPanda 收藏书签|收藏状态变了之后，书签跟着换了")

        XCTAssertEqual(app.state, .runningForeground, "测试结束时 App 应该仍在前台运行")
    }

    /// 新写的哔咔界面要自己给请求签名。这里拿上游客户端的实现和新写的实现对同样的输入各算一遍，
    /// 确认包括签名在内的每一个请求头都一样。上游的代码还在安装包里，测试页面把它载入进来对。
    /// 这一项不联网：验证的是「算得和上游一样」，服务器认不认要登录之后才知道。
    @MainActor
    func testBikaRequestHeadersMatchUpstream() throws {
        let app = makeApp(["-hub.autoEnterLastModule", "NO", "-hub.probe", "bikaSignature"])
        app.launch()

        let result = element("probe.bika.signature", in: app)
        XCTAssertTrue(
            waitUntil(timeout: 90) { result.exists && result.label.contains("请求头") },
            "没有读到哔咔请求签名的自检结果"
        )
        print("HUBUI|哔咔的请求签名|\(result.label)")
        XCTAssertTrue(result.label.contains("文字编码和系统的一样：是"), "分类名、搜索词的编码和系统的结果不一样")
        XCTAssertTrue(result.label.contains("全部一样"), "新写的请求头和上游算出来的不一样，见测试结果里的「哔咔的请求签名」")

        XCTAssertEqual(app.state, .runningForeground, "测试结束时 App 应该仍在前台运行")
    }

    /// 新写的哔咔界面，接口换成一份假数据（真的接口要登录），从登录页一路走到阅读页：
    /// 密码不对有提示、登录成功进首页 → 点分类进列表、滑到底会自动取下一页 → 进详情、收藏按钮能切换
    /// → 开始阅读、滑到一话的结尾（中间要自动取两次后面的图片）→ 从屏幕左边缘右滑回到详情页，
    /// 并且记住了看到哪里 → 「我的」里能打卡、浏览历史里有刚才那一本。
    /// 假数据里没有任何真实内容，所以界面上的文字可以照常记录。
    @MainActor
    func testBikaFlowWithFakeData() throws {
        let app = makeApp(["-hub.autoEnterLastModule", "NO", "-hub.probe", "bikaFlow"])
        app.launch()

        // 登录页。密码框里按回车就是提交，免得键盘挡住「登录」按钮。
        let account = element("bika.login.account", in: app)
        let password = element("bika.login.password", in: app)
        XCTAssertTrue(account.waitForExistence(timeout: 90), "没有出现新版哔咔的登录页")
        account.tap()
        account.typeText("probe")
        password.tap()
        password.typeText("wrong\n")
        let loginError = element("bika.login.error", in: app)
        XCTAssertTrue(loginError.waitForExistence(timeout: 20), "密码不对时登录页没有给出提示")
        print("HUBUI|新版哔咔|密码不对时的提示：\(loginError.label)")
        XCTAssertTrue(loginError.label.contains("账号或密码不对"), "密码不对时的提示不是预期的那一句")

        password.tap()
        password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "probe\n")

        // 首页。登录成功之后系统可能弹出「要不要存储密码」，会挡住界面，有的话先点掉。
        let category = element("bika.category.mock-category-1", in: app)
        XCTAssertTrue(category.waitForExistence(timeout: 30), "登录之后没有出现首页的分类")
        settle(2)
        dismissSavePasswordPrompt(in: app)
        settle(1)
        report("新版哔咔的首页", app)
        category.tap()

        // 列表：第一页出来了；往下滑，第二页自动取回来。
        let firstComic = element("bika.comic.mock-1", in: app)
        XCTAssertTrue(firstComic.waitForExistence(timeout: 30), "点分类之后没有出现漫画列表")
        let secondPageComic = element("bika.comic.mock-21", in: app)
        var listSwipes = 0
        while !secondPageComic.exists, listSwipes < 15 {
            app.swipeUp()
            listSwipes += 1
        }
        XCTAssertTrue(secondPageComic.waitForExistence(timeout: 15), "列表滑到底之后没有自动取下一页")
        print("HUBUI|新版哔咔|列表往下滑了 \(listSwipes) 次，第二页取回来了")
        secondPageComic.tap()

        // 详情。
        let title = element("bika.detail.title", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 30), "点漫画之后没有进入详情页")
        XCTAssertEqual(title.label, "测试漫画 21")
        XCTAssertTrue(element("bika.episode.1", in: app).waitForExistence(timeout: 30), "详情页里没有出现章节")
        let favourite = element("bika.detail.favourite", in: app)
        XCTAssertTrue(favourite.exists, "详情页里没有收藏按钮")
        XCTAssertFalse(favourite.label.contains("已收藏"), "还没点过收藏，按钮不应该是已收藏")
        favourite.tap()
        XCTAssertTrue(waitUntil(timeout: 20) { favourite.label.contains("已收藏") }, "点收藏之后按钮没有变成已收藏")
        settle(1)
        report("新版哔咔的详情页", app)

        // 阅读：一话 12 张，一次只取 4 张。
        let read = element("bika.detail.read", in: app)
        XCTAssertTrue(read.label.contains("开始阅读"), "没看过的漫画，阅读按钮应当是「开始阅读」")
        read.tap()
        XCTAssertTrue(element("bika.reader.page.0", in: app).waitForExistence(timeout: 30), "点开始阅读之后没有进入阅读页")
        let progress = element("bika.reader.progress", in: app)
        XCTAssertTrue(
            waitUntil(timeout: 20) { progress.exists && progress.label.contains("1 / 12") },
            "阅读页一开始的进度不是第 1 张、共 12 张"
        )
        let episodeEnd = element("bika.reader.end", in: app)
        var readerSwipes = 0
        while !episodeEnd.exists, readerSwipes < 25 {
            app.swipeUp()
            readerSwipes += 1
        }
        XCTAssertTrue(episodeEnd.waitForExistence(timeout: 15), "阅读页滑到底没有到这一话的结尾，后面的图片没有取回来")
        XCTAssertTrue(element("bika.reader.next", in: app).exists, "第一话看完之后应当有「下一话」的按钮")
        print("HUBUI|新版哔咔|阅读页往下滑了 \(readerSwipes) 次到这一话的结尾，这时的进度：\(progress.exists ? progress.label : "读不到")")
        XCTAssertFalse(progress.label.contains("　1 / 12"), "滑到结尾之后，进度还停在第 1 张")

        // 从屏幕左边缘右滑：回到详情页，并且记住了看到哪里。
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 3, dy: 0))
        let target = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: target)
        XCTAssertTrue(title.waitForExistence(timeout: 20), "在阅读页从屏幕左边缘右滑，没有回到详情页")
        XCTAssertTrue(waitUntil(timeout: 20) { read.exists && read.label.contains("接着看") }, "回到详情页之后，没有记住看到哪里")
        print("HUBUI|新版哔咔|从屏幕左边缘右滑回到了详情页，阅读按钮变成：\(read.label)")

        // 「我的」：资料取到了，能打卡；浏览历史里有刚才那一本。
        let profileTab = app.tabBars.buttons["我的"].exists ? app.tabBars.buttons["我的"] : app.buttons["我的"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 15), "底部没有「我的」这个标签")
        profileTab.tap()
        let punch = element("bika.profile.punch", in: app)
        XCTAssertTrue(punch.waitForExistence(timeout: 30), "「我的」页面上没有打卡按钮，资料没有取到")
        punch.tap()
        XCTAssertTrue(waitUntil(timeout: 20) { punch.label.contains("已打卡") }, "点打卡之后按钮没有变成已打卡")
        settle(1)
        report("新版哔咔的「我的」", app)
        element("bika.profile.history", in: app).tap()
        XCTAssertTrue(app.staticTexts["测试漫画 21"].waitForExistence(timeout: 20), "浏览历史里没有刚才看的那一本")
        report("新版哔咔的浏览历史", app)

        XCTAssertEqual(app.state, .runningForeground, "测试结束时 App 应该仍在前台运行")
    }

    /// Pixiv 的颜色预设已经去掉：设置向导的「外观与画质」一步里只剩主题模式，没有「主题强调色」。
    ///
    /// 向导不需要登录，也不联网。这个测试停在向导的最后一步，不点「完成设置」，
    /// 所以别的测试进入 Pixiv 时看到的仍然是向导的第一步。
    @MainActor
    func testPixivOnboardingHasNoThemeColorPresets() throws {
        let app = makeApp(["-hub.autoEnterLastModule", "YES", "-hub.lastModule", "pixiv"])
        app.launch()

        let switcher = element("hub.switcher", in: app)
        XCTAssertTrue(switcher.waitForExistence(timeout: 60), "没有直接进入上次使用的应用")
        XCTAssertEqual(switcher.value as? String, "Pixiv")

        let start = app.buttons["开始设置"]
        try XCTSkipUnless(start.waitForExistence(timeout: 30), "没有出现 Pixiv 的设置向导（可能已经走完过）")
        start.tap()

        // 欢迎 → 网络 → 内容过滤 → 外观与画质。
        let next = app.buttons["下一步"]
        XCTAssertTrue(app.staticTexts["步骤 2 / 4"].waitForExistence(timeout: 15), "点「开始设置」后没有进入向导第 2 步")
        next.tap()
        XCTAssertTrue(app.staticTexts["步骤 3 / 4"].waitForExistence(timeout: 15), "没有进入向导第 3 步")
        next.tap()
        XCTAssertTrue(app.staticTexts["步骤 4 / 4"].waitForExistence(timeout: 15), "没有进入向导第 4 步")

        XCTAssertTrue(app.staticTexts["界面主题模式"].waitForExistence(timeout: 10), "向导第 4 步里没有找到「界面主题模式」")
        XCTAssertFalse(app.staticTexts["主题强调色"].exists, "向导第 4 步里不应该再有「主题强调色」")
        report("Pixiv 向导第 4 步", app)

        XCTAssertEqual(app.state, .runningForeground, "测试结束时 App 应该仍在前台运行")
    }

    /// Pixiv 详情页的多图翻页在左侧让出了一条区域（`PixivPagerEdgeGuard`），留给右滑返回。
    ///
    /// 详情页要登录才进得去，所以这里用调试构建里的测试页面（`HubProbe`）来验证。它和详情页是同样的
    /// 结构：导航栈里推入的一页、上下滚动、顶部是左右翻页的图片区，图片区左侧盖着同一个让出区域。
    @MainActor
    func testPagerEdgeGuardLeavesLeftStripToBackSwipe() throws {
        let app = makeApp(["-hub.autoEnterLastModule", "NO", "-hub.probe", "pagerEdgeGuard"])
        app.launch()

        let page = element("probe.page", in: app)
        let root = element("probe.root", in: app)
        XCTAssertTrue(page.waitForExistence(timeout: 60), "没有打开翻页测试页面")
        // 页面刚出来时界面还没稳下来，模拟器卡的时候这时去读内容会超时，所以先等一等。
        settle(3)
        XCTAssertEqual(page.label, "1")

        // 在让出区域以外，翻页照常：从中间向左滑到第 2 页，向右滑回第 1 页，再滑到第 2 页。
        XCTAssertTrue(
            dragAcrossPager(in: app, from: 0.8, to: 0.15, until: page, shows: "2"),
            "从图片中间向左滑，没有翻到第 2 页"
        )
        XCTAssertTrue(
            dragAcrossPager(in: app, from: 0.4, to: 0.95, until: page, shows: "1"),
            "从图片中间向右滑，没有翻回第 1 页"
        )
        XCTAssertTrue(
            dragAcrossPager(in: app, from: 0.8, to: 0.15, until: page, shows: "2"),
            "第二次向左滑，没有翻到第 2 页"
        )

        // 轻点：让出区域里的轻点交给它自己的回调（详情页里是打开大图），区域以外的轻点落在图片上。
        let guardTaps = element("probe.guardTaps", in: app)
        let imageTaps = element("probe.imageTaps", in: app)
        pagerPoint(in: app, pointsFromLeft: 22).tap()
        XCTAssertTrue(waitUntil(timeout: 5) { guardTaps.label == "1" }, "轻点让出区域没有触发它的回调")
        pagerPoint(in: app, pointsFromLeft: 200).tap()
        XCTAssertTrue(waitUntil(timeout: 5) { imageTaps.label == "1" }, "轻点让出区域以外的图片，没有触发图片自己的点击")
        XCTAssertEqual(page.label, "2", "轻点不应该翻页")

        // 从让出区域里向右滑：不能翻页。系统会不会把它当成返回由系统决定，这里只记录。
        dragRightAcrossPager(in: app, pointsFromLeft: 30)
        let poppedFromStrip = waitUntil(timeout: 4) { !page.exists }
        if !poppedFromStrip {
            XCTAssertEqual(page.label, "2", "从图片左侧让出的区域向右滑，不应该翻页")
        }
        print("HUBUI|翻页左侧让出区域|从让出区域里（距左边缘 30 点）右滑：\(poppedFromStrip ? "返回了上一级" : "没有翻页，也没有返回")")

        // 在图片区的高度上，从屏幕最左边缘向右滑：必须能返回上一级。
        if !poppedFromStrip {
            dragRightAcrossPager(in: app, pointsFromLeft: 3)
            XCTAssertTrue(waitUntil(timeout: 10) { !page.exists }, "在翻页区域的高度上从屏幕左边缘右滑，没有返回上一级")
            print("HUBUI|翻页左侧让出区域|从屏幕左边缘（距左边缘 3 点）右滑：返回了上一级")
        }
        XCTAssertTrue(root.waitForExistence(timeout: 10), "返回之后没有回到测试首页")

        // 对照：同样的页面不盖让出区域，从同样的位置右滑会怎样。这是系统自己的行为，只记录，不判定。
        app.terminate()
        settle(3)
        let bare = makeApp(["-hub.autoEnterLastModule", "NO", "-hub.probe", "pagerWithoutGuard"])
        bare.launch()
        let barePage = element("probe.page", in: bare)
        guard barePage.waitForExistence(timeout: 60) else {
            print("HUBUI|翻页左侧让出区域|对照页面没有打开，跳过对照")
            return
        }
        settle(2)
        for pointsFromLeft in [CGFloat(30), CGFloat(3)] {
            guard barePage.exists else { break }
            if barePage.label != "2" {
                guard dragAcrossPager(in: bare, from: 0.8, to: 0.15, until: barePage, shows: "2") else { break }
            }
            dragRightAcrossPager(in: bare, pointsFromLeft: pointsFromLeft)
            settle(3)
            let outcome: String
            if !barePage.exists {
                outcome = "返回了上一级"
            } else if barePage.label == "1" {
                outcome = "翻回了第 1 页"
            } else {
                outcome = "没有翻页，也没有返回"
            }
            print("HUBUI|翻页左侧让出区域|对照（不盖让出区域）从距左边缘 \(Int(pointsFromLeft)) 点处右滑：\(outcome)")
        }
    }

    // MARK: 辅助方法

    /// 启动页是照着系统「图书」做的书架：两个分区标题都在，三本书互不重叠、都在屏幕以内，
    /// 竖屏的 iPhone 上排在同一排。样子（封面的颜色、圆角、阴影）这里看不到，只能查位置。
    @MainActor
    private func checkLauncherShelf(in app: XCUIApplication) {
        for title in ["应用", "启动"] {
            let header = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
            XCTAssertTrue(header.exists, "启动页上没有「\(title)」这个分区标题")
        }

        // 前三本是三个上游应用，第四本是新写的哔咔界面。
        let names = ["ehpanda", "pixiv", "pica", "bika"]
        let frames = names.map { element("hub.module.\($0)", in: app).frame }
        let screen = app.frame
        print("HUBUI|启动页|几本书的位置：" + zip(names, frames).map { "\($0) \(describe($1))" }.joined(separator: "；")
            + "；屏幕 \(describe(screen))")

        for (name, frame) in zip(names, frames) {
            XCTAssertFalse(frame.isEmpty, "启动页上没有出现 \(name) 的那本书")
            XCTAssertTrue(screen.contains(frame), "启动页上 \(name) 的那本书有一部分在屏幕外面")
            // 封面是 2:3 的竖长方形，下面还有两三行字，所以整本书一定比它的宽度高出一半以上。
            XCTAssertGreaterThan(frame.height, frame.width * 1.5, "启动页上 \(name) 的那本书不是竖长的封面")
        }
        for first in frames.indices {
            for second in frames.indices where second > first {
                XCTAssertFalse(
                    frames[first].intersects(frames[second]),
                    "启动页上 \(names[first]) 和 \(names[second]) 两本书压在了一起"
                )
            }
        }
        if UIDevice.current.userInterfaceIdiom == .phone, screen.width < screen.height {
            // 竖屏的 iPhone 一排放三本，第四本换到下一排（屏幕更宽的机型上也可能还在同一排，所以只要求它不在上面）。
            XCTAssertGreaterThanOrEqual(frames[3].minY, frames[0].minY - 1, "第四本书不应该排到前三本的上面")
            XCTAssertEqual(frames[0].minY, frames[1].minY, accuracy: 1, "竖屏的 iPhone 上，三本书应当排在同一排")
            XCTAssertEqual(frames[1].minY, frames[2].minY, accuracy: 1, "竖屏的 iPhone 上，三本书应当排在同一排")
            XCTAssertLessThan(frames[0].minX, frames[1].minX, "三本书应当按 EhPanda、Pixiv、Pica 的顺序从左到右排")
            XCTAssertLessThan(frames[1].minX, frames[2].minX, "三本书应当按 EhPanda、Pixiv、Pica 的顺序从左到右排")
        }
    }

    /// 在 EhPanda 里走一遍：必要时走过首次启动的两页 → 滑到主页底部点开「AI 热门」→ 从屏幕左边缘右滑返回主页。
    /// 主页的内容不截图也不打印，这里只关心入口在不在、页面能不能打开、侧滑返回管不管用。
    @MainActor
    private func checkEhPandaAIPopularAndEdgeSwipeBack(in app: XCUIApplication, group: String) {
        // 首次启动：勾选成年声明 → 继续 → 选统计级别 → 继续。之前已经走过的话就跳过。
        let declaration = element("first_launch_declaration", in: app)
        let entry = element("home_ai_popular_entry", in: app)
        XCTAssertTrue(
            waitUntil(timeout: 60) { declaration.exists || entry.exists },
            "进入 EhPanda 后既没有出现成年确认页，也没有出现主页"
        )
        if declaration.exists {
            declaration.tap()
            element("first_launch_continue", in: app).tap()
            let level = element("first_launch_level_minimal", in: app)
            XCTAssertTrue(level.waitForExistence(timeout: 30), "成年确认之后没有出现统计选项页")
            level.tap()
            element("first_launch_continue", in: app).tap()
        }

        // 主页：入口在最底部，往上滑到它能点到为止。
        XCTAssertTrue(entry.waitForExistence(timeout: 60), "EhPanda 主页上没有「AI 热门」入口")
        var swipes = 0
        while !entry.isHittable, swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(entry.isHittable, "滑到主页底部后仍然点不到「AI 热门」入口")
        entry.tap()

        // 页面推入之后，主页不在界面层级里了，入口也就找不到了。
        XCTAssertTrue(waitUntil(timeout: 30) { !entry.exists }, "点「AI 热门」入口后没有打开新页面")
        let titleShown = waitUntil(timeout: 10) { app.navigationBars["AI 热门"].exists }
        print("HUBUI|\(group)|「AI 热门」页面已打开，导航栏标题是「AI 热门」：\(titleShown ? "是" : "没有识别到")")

        // 从屏幕左边缘向右滑，应当返回主页。
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 3, dy: 0))
        let target = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: target)
        XCTAssertTrue(entry.waitForExistence(timeout: 15), "从屏幕左边缘右滑之后没有返回主页")
        print("HUBUI|\(group)|从屏幕左边缘右滑：已返回主页")
    }

    /// 在图片区上横向拖动，直到页码变成想要的那一页。
    /// 模拟器卡的时候，一次拖动可能没被当成翻页就弹回去了，所以没翻过去就再拖一次，最多三次。
    @MainActor
    private func dragAcrossPager(
        in app: XCUIApplication, from: CGFloat, to: CGFloat, until page: XCUIElement, shows expected: String
    ) -> Bool {
        for attempt in 1...3 {
            dragAcrossPager(in: app, from: from, to: to)
            if waitUntil(timeout: 10, { page.exists && page.label == expected }) {
                if attempt > 1 {
                    print("HUBUI|翻页测试|拖了 \(attempt) 次才翻到第 \(expected) 页（模拟器卡）")
                }
                return true
            }
        }
        return false
    }

    /// 翻页测试页面里图片区上的一个点：距屏幕左边缘 `pointsFromLeft` 点，高度在图片区中间。
    @MainActor
    private func pagerPoint(in app: XCUIApplication, pointsFromLeft: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.3))
            .withOffset(CGVector(dx: pointsFromLeft, dy: 0))
    }

    /// 在图片区上横向拖动，起点和终点用屏幕宽度的比例表示。
    @MainActor
    private func dragAcrossPager(in app: XCUIApplication, from: CGFloat, to: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// 在图片区上从距屏幕左边缘 `pointsFromLeft` 点的地方向右拖到屏幕右侧。
    @MainActor
    private func dragRightAcrossPager(in app: XCUIApplication, pointsFromLeft: CGFloat) {
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.3))
        pagerPoint(in: app, pointsFromLeft: pointsFromLeft).press(forDuration: 0.05, thenDragTo: end)
    }

    /// 系统问「要不要存储密码」的提示框：有的话点「以后」。它有时算在 App 里，有时算在系统桌面里，两边都找。
    @MainActor
    private func dismissSavePasswordPrompt(in app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for host in [app, springboard] {
            for label in ["以后", "Not Now"] {
                let button = host.buttons[label]
                if button.exists {
                    print("HUBUI|新版哔咔|系统问要不要存储密码，点了「\(label)」")
                    button.tap()
                    return
                }
            }
        }
    }

    @MainActor
    private func makeApp(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = languageArguments + arguments
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// 等界面稳定下来（模块自己的启动初始化、转场动画）。
    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// 每隔半秒检查一次条件，直到满足或者超时。
    @MainActor
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return condition()
    }

    private func describe(_ rect: CGRect) -> String {
        "x=\(Int(rect.minX)) y=\(Int(rect.minY)) 宽=\(Int(rect.width)) 高=\(Int(rect.height))"
    }

    /// 截一张图存进测试结果，并把屏幕上的文字打印出来。
    /// 悬浮按钮在场时，还会报告它的位置，以及它有没有压在别的按钮上。
    ///
    /// EhPanda 过了成年确认页之后、Pica 登录之后的界面是站点内容，不截图也不打印：
    /// 这些测试结果会出现在公开仓库的构建记录里。
    @MainActor
    private func report(_ name: String, _ app: XCUIApplication) {
        let switcher = element("hub.switcher", in: app)
        let isInEhPanda = switcher.exists && (switcher.value as? String) == "EhPanda"
        let isOnFirstLaunchPages = element("first_launch_age_wall_title", in: app).exists
            || element("first_launch_analytics_title", in: app).exists
        if isInEhPanda && !isOnFirstLaunchPages {
            print("HUBUI|\(name)|（已经在 EhPanda 的内容页面里，不截图也不记录文字）")
            return
        }
        // Pica 同理：登录之后看到的是站点内容。没登录时只有登录页（或者载入失败的说明），可以记录。
        let isInPica = switcher.exists && (switcher.value as? String) == "Pica"
        let isOnPicaStaticPages = app.buttons["登录"].exists || element("pica.loadFailure", in: app).exists
        if isInPica && !isOnPicaStaticPages {
            print("HUBUI|\(name)|（已经在 Pica 的内容页面里，不截图也不记录文字）")
            return
        }

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        var texts: [String] = []
        var buttons: [(label: String, frame: CGRect)] = []
        var switcherFrame: CGRect?
        do {
            try inspect(app.snapshot(), texts: &texts, buttons: &buttons, switcherFrame: &switcherFrame)
        } catch {
            print("HUBUI|\(name)|（读取界面内容失败：\(error.localizedDescription)）")
        }

        print("HUBUI|\(name)|（共 \(texts.count) 项）")
        for text in texts.prefix(50) {
            print("HUBUI|\(name)|\(text)")
        }
        if let switcherFrame {
            let covered = buttons.filter { $0.frame.intersects(switcherFrame) }.map { $0.label }
            let verdict = covered.isEmpty ? "没有压住别的按钮" : "压住了这些按钮：" + covered.joined(separator: "、")
            print("HUBUI|\(name)|〔悬浮按钮 \(describe(switcherFrame))，屏幕 \(describe(app.frame))，\(verdict)〕")
        }
    }

    private func inspect(
        _ snapshot: any XCUIElementSnapshot,
        texts: inout [String],
        buttons: inout [(label: String, frame: CGRect)],
        switcherFrame: inout CGRect?
    ) {
        let label = String(
            snapshot.label
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
                .prefix(80)
        )

        if snapshot.identifier == "hub.switcher" {
            switcherFrame = snapshot.frame
        } else if snapshot.elementType == .button, !label.isEmpty {
            buttons.append((label, snapshot.frame))
        }

        switch snapshot.elementType {
        case .staticText, .button, .navigationBar, .tab, .textField, .secureTextField, .link:
            if !label.isEmpty, !texts.contains(label) {
                texts.append(label)
            }
        default:
            break
        }
        for child in snapshot.children {
            inspect(child, texts: &texts, buttons: &buttons, switcherFrame: &switcherFrame)
        }
    }
}
