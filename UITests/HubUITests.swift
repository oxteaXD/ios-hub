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

    /// 截一张图存进测试结果，并把屏幕上的文字打印出来。
    @MainActor
    private func report(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        var texts: [String] = []
        do {
            try collectTexts(from: app.snapshot(), into: &texts)
        } catch {
            print("HUBUI|\(name)|（读取界面内容失败：\(error.localizedDescription)）")
        }
        print("HUBUI|\(name)|（共 \(texts.count) 项）")
        for text in texts.prefix(50) {
            print("HUBUI|\(name)|\(text)")
        }
    }

    private func collectTexts(from snapshot: any XCUIElementSnapshot, into texts: inout [String]) {
        switch snapshot.elementType {
        case .staticText, .button, .navigationBar, .tab, .textField, .secureTextField, .link:
            let label = snapshot.label
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            let text = String(label.prefix(80))
            if !text.isEmpty, !texts.contains(text) {
                texts.append(text)
            }
        default:
            break
        }
        for child in snapshot.children {
            collectTexts(from: child, into: &texts)
        }
    }
}
