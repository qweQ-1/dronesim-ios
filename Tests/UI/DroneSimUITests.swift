import XCTest

/// UI 冒烟测试：验证 App 能启动、关键控件存在、可交互。
final class DroneSimUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// 启动 App 并等到 HUD 出现（渲染已就绪）。
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()

        // HUD 里的标签显式设了 accessibilityIdentifier。
        // Metal 视图没有无障碍元素，所以用 HUD 作为「App 已渲染」的信号。
        let hud = app.staticTexts["hud.altitude.caption"]
        if hud.waitForExistence(timeout: 30) {
            return app
        }
        // 兜底：任意可访问元素出现即认为 App 已启动
        let anyElement = app.descendants(matching: .any).firstMatch
        XCTAssertTrue(anyElement.waitForExistence(timeout: 15),
                      "App 启动后应有可访问元素（截图 app.debugDescription 看无障碍树）")
        return app
    }

    /// App 启动后关键控件都在。
    func testMainScreenShowsControls() {
        let app = launchApp()

        XCTAssertTrue(app.buttons["button.arm"].exists, "应有起飞按钮")
        XCTAssertTrue(app.buttons["button.camera"].exists, "应有视角按钮")
        XCTAssertTrue(app.buttons["button.mode"].exists, "应有自稳按钮")
        XCTAssertTrue(app.buttons["button.altitude"].exists, "应有定高按钮")
    }

    /// 点击「起飞」应该变成「上锁」。
    func testArmButtonToggles() {
        let app = launchApp()

        let armButton = app.buttons["button.arm"]
        XCTAssertTrue(armButton.waitForExistence(timeout: 15))
        armButton.tap()

        // 上锁后按钮的无障碍标签会更新为「上锁」
        let locked = app.buttons["button.arm"]
        let predicate = NSPredicate(format: "label == %@", "上锁")
        expectation(for: predicate, evaluatedWith: locked)
        waitForExpectations(timeout: 15)
    }

    /// 视角切换应该出现提示文本。
    func testCameraButtonCyclesViews() {
        let app = launchApp()

        let cameraButton = app.buttons["button.camera"]
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 15))
        cameraButton.tap()

        let fpv = app.staticTexts["机载视角"]
        XCTAssertTrue(fpv.waitForExistence(timeout: 15), "应提示切换到机载视角")
    }
}
