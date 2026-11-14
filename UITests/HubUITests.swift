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

    /// 按住悬浮按钮可以拖到屏幕另一侧，松手后吸附在那一侧。
    @MainActor
    func testDraggingSwitcherMovesItToTheOtherSide() throws {
        let app = makeApp(["-hub.autoEnterLastModule", "YES", "-hub.lastModule", "ehpanda"])
        app.launch()

        let switcher = element("hub.switcher", in: app)
        XCTAssertTrue(switcher.waitForExistence(timeout: 60), "没有直接进入上次使用的应用")
        settle(3)

        // 之前的测试可能已经把它挪过位置，所以先看它现在在哪一侧，再往另一侧拖。
        let before = switcher.frame
        let startsOnRight = before.midX > app.frame.midX
        let start = switcher.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: startsOnRight ? 0.2 : 0.8, dy: 0.35))
        start.press(forDuration: 0.1, thenDragTo: end)
        settle(2)

        let after = switcher.frame
        print("HUBUI|拖动悬浮按钮|拖动前 \(describe(before))，拖动后 \(describe(after))，屏幕 \(describe(app.frame))")
        if startsOnRight {
            XCTAssertLessThan(after.midX, app.frame.midX, "往左拖之后，悬浮按钮应该吸附在左侧")
        } else {
            XCTAssertGreaterThan(after.midX, app.frame.midX, "往右拖之后，悬浮按钮应该吸附在右侧")
        }
        XCTAssertEqual(switcher.value as? String, "EhPanda", "拖动不应该触发切换")
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
    @MainActor
    private func report(_ name: String, _ app: XCUIApplication) {
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
