import XCTest

/// UI 冒烟测试：验证 App 能启动、关键控件存在、可交互。
final class DroneSimUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// 启动 App 并等到 HUD 出现（渲染已就绪）。
    ///
    /// Metal 视图要初始化几百个实例，首次启动偏慢，
    /// 所以这里给足等待时间，并且用「任意可访问元素」做兜底判断。
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()

        // app.ready 是世界构建完成时设置的标记（1x1 像素，不挡任何东西）
        let ready = app.staticTexts["app.ready"]
        if ready.waitForExistence(timeout: 60) {
            return app
        }

        // 兜底：控制层里的按钮（OverlayButton 标了 .button 角色）
        let armButton = app.buttons["button.arm"]
        if armButton.waitForExistence(timeout: 30) {
            return app
        }

        // 再兜底：HUD 标签
        let hud = app.staticTexts["hud.altitude.caption"]
        if hud.waitForExistence(timeout: 15) {
            return app
        }

        // 最后的兜底：任意元素
        let anyElement = app.descendants(matching: .any).firstMatch
        if !anyElement.waitForExistence(timeout: 15) {
            // 把无障碍树写到测试产出的附件里，方便 CI 日志排查
            let tree = app.debugDescription
            let attachment = XCTAttachment(string: tree)
            attachment.name = "accessibility-tree"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTFail("App 启动后应有可访问元素。无障碍树：\n\(tree)")
        }
        return app
    }

    /// App 启动后关键控件都在。
    func testMainScreenShowsControls() {
        let app = launchApp()

        for identifier in ["button.arm", "button.camera", "button.mode", "button.altitude"] {
            if !app.buttons[identifier].exists {
                let attachment = XCTAttachment(string: app.debugDescription)
                attachment.name = "accessibility-tree-\(identifier)"
                attachment.lifetime = .keepAlways
                add(attachment)
                XCTFail("应存在 \(identifier)")
            }
        }
    }

    /// 点击「起飞」应该变成「上锁」。
    func testArmButtonToggles() {
        let app = launchApp()

        let armButton = app.buttons["button.arm"]
        XCTAssertTrue(armButton.waitForExistence(timeout: 30))
        armButton.tap()

        // 上锁后按钮的无障碍标签会更新为「上锁」
        let predicate = NSPredicate(format: "label == %@", "上锁")
        expectation(for: predicate, evaluatedWith: armButton)
        waitForExpectations(timeout: 20)
    }

    /// 视角切换应该出现提示文本。
    func testCameraButtonCyclesViews() {
        let app = launchApp()

        let cameraButton = app.buttons["button.camera"]
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 30))
        cameraButton.tap()

        let fpv = app.staticTexts["机载视角"]
        XCTAssertTrue(fpv.waitForExistence(timeout: 20), "应提示切换到机载视角")
    }
}
