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

        XCTAssertTrue(ehpandaCard.waitForExistence(timeout: 60), "启动页上没有出现 EhPanda 的卡片")
        XCTAssertTrue(pixivCard.exists, "启动页上没有出现 Pixiv 的卡片")
        XCTAssertFalse(switcher.exists, "启动页上不应该有悬浮按钮")
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

        // 首次启动：勾选成年声明 → 继续 → 选统计级别 → 继续。之前的测试已经走过的话就跳过。
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
        print("HUBUI|AI 热门入口|页面已打开，导航栏标题是「AI 热门」：\(titleShown ? "是" : "没有识别到")")

        // 从屏幕左边缘向右滑，应当返回主页。
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 3, dy: 0))
        let target = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: target)
        XCTAssertTrue(entry.waitForExistence(timeout: 15), "从屏幕左边缘右滑之后没有返回主页")
        print("HUBUI|AI 热门入口|从屏幕左边缘右滑：已返回主页")

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

    // MARK: 辅助方法

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
    /// EhPanda 过了成年确认页之后的界面是站点内容，不截图也不打印：
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
