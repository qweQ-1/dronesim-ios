import XCTest

/// UI 冒烟测试：验证 App 能启动、关键控件存在、可交互。
final class DroneSimUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// App 启动后应该能看到主要控件。
    func testMainScreenShowsControls() {
        let app = XCUIApplication()
        app.launch()

        // 等渲染画面出现（Metal 视图没有 accessibility 元素，用 HUD 文本判断就绪）
        let altitude = app.staticTexts["高度 m"]
        XCTAssertTrue(altitude.waitForExistence(timeout: 20), "启动后应显示 HUD")
    }

    /// 点击「起飞」应该改变按钮标题。
    func testArmButtonToggles() {
        let app = XCUIApplication()
        app.launch()

        let altitude = app.staticTexts["高度 m"]
        XCTAssertTrue(altitude.waitForExistence(timeout: 20))

        let armButton = app.staticTexts["起飞"].firstMatch
        XCTAssertTrue(armButton.waitForExistence(timeout: 5), "应能看到起飞按钮")

        armButton.tap()

        // 点击后按钮变成「上锁」
        let locked = app.staticTexts["上锁"].firstMatch
        XCTAssertTrue(locked.waitForExistence(timeout: 5), "点击起飞后按钮应变为上锁")
    }

    /// 视角切换按钮应能改变提示文本。
    func testCameraButtonCyclesViews() {
        let app = XCUIApplication()
        app.launch()

        let altitude = app.staticTexts["高度 m"]
        XCTAssertTrue(altitude.waitForExistence(timeout: 20))

        let cameraButton = app.staticTexts["视角"].firstMatch
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 5))
        cameraButton.tap()

        let fpv = app.staticTexts["机载视角"].firstMatch
        XCTAssertTrue(fpv.waitForExistence(timeout: 5), "应提示切换到机载视角")
    }
}
