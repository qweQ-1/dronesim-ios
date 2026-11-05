import Foundation
import UIKit

// MARK: - 控制覆盖层

/// 覆盖在渲染画面上的控制层。
/// 摇杆本身是子视图（`VirtualJoystick`），触摸由 GameViewController 统一分发，
/// 这样按钮和摇杆可以共存而不互相抢事件。
final class ControlOverlayView: UIView {

    /// 左摇杆（油门/偏航）。
    let leftStick = VirtualJoystick()
    /// 右摇杆（横滚/俯仰）。
    let rightStick = VirtualJoystick()

    let armButton = OverlayButton(title: "起飞", symbol: "power")
    let cameraButton = OverlayButton(title: "视角", symbol: "video")
    let modeButton = OverlayButton(title: "自稳", symbol: "gyroscope")
    let altitudeButton = OverlayButton(title: "定高", symbol: "arrow.up.to.line")
    let motionButton = OverlayButton(title: "体感", symbol: "gyroscope")
    let pauseButton = OverlayButton(title: "暂停", symbol: "pause")
    let resetButton = OverlayButton(title: "复位", symbol: "arrow.counterclockwise")

    /// 给 UI 测试用的启动标记。
    ///
    /// 放在左上角、1x1 像素、不挡任何可点区域；
    /// 用来确认 App 已经完成渲染（世界构建完成）。
    private let readyMarker = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear

        leftStick.translatesAutoresizingMaskIntoConstraints = false
        rightStick.translatesAutoresizingMaskIntoConstraints = false
        leftStick.isLeftStick = true
        rightStick.isLeftStick = false
        addSubview(leftStick)
        addSubview(rightStick)
        // 摇杆铺满半屏，会在无障碍树里遮挡按钮 —— 让它不参与无障碍。
        leftStick.isAccessibilityElement = false
        rightStick.isAccessibilityElement = false
        leftStick.accessibilityElementsHidden = true
        rightStick.accessibilityElementsHidden = true

        // 启动标记
        readyMarker.translatesAutoresizingMaskIntoConstraints = false
        readyMarker.text = "ready"
        readyMarker.textColor = .clear
        readyMarker.font = .systemFont(ofSize: 1)
        readyMarker.isAccessibilityElement = true
        readyMarker.accessibilityIdentifier = "app.ready"
        readyMarker.accessibilityLabel = "ready"
        addSubview(readyMarker)
        NSLayoutConstraint.activate([
            readyMarker.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            readyMarker.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            readyMarker.widthAnchor.constraint(equalToConstant: 1),
            readyMarker.heightAnchor.constraint(equalToConstant: 1),
        ])

        // 摇杆视图铺满左右半屏，这样屏幕上任何位置的拖动都能被对应的摇杆捕获，
        // 而摇杆图案只画在实际接触点附近（见 VirtualJoystick 的绘制逻辑）。
        NSLayoutConstraint.activate([
            leftStick.topAnchor.constraint(equalTo: topAnchor),
            leftStick.bottomAnchor.constraint(equalTo: bottomAnchor),
            leftStick.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftStick.trailingAnchor.constraint(equalTo: centerXAnchor),

            rightStick.topAnchor.constraint(equalTo: topAnchor),
            rightStick.bottomAnchor.constraint(equalTo: bottomAnchor),
            rightStick.leadingAnchor.constraint(equalTo: centerXAnchor),
            rightStick.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // 按钮组：右侧竖排
        let buttons = [armButton, cameraButton, modeButton, altitudeButton,
                       motionButton, pauseButton, resetButton]
        armButton.setIdentifier("button.arm")
        cameraButton.setIdentifier("button.camera")
        modeButton.setIdentifier("button.mode")
        altitudeButton.setIdentifier("button.altitude")
        motionButton.setIdentifier("button.motion")
        pauseButton.setIdentifier("button.pause")
        resetButton.setIdentifier("button.reset")
        var previousButton: OverlayButton?
        for button in buttons {
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 52),
                button.heightAnchor.constraint(equalToConstant: 52),
                button.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -18),
            ])
            if let previousButton {
                button.topAnchor.constraint(equalTo: previousButton.bottomAnchor, constant: 9).isActive = true
            } else {
                button.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 52).isActive = true
            }
            previousButton = button
        }
    }
}

// MARK: - 动作绑定

extension ControlOverlayView {
    /// 绑定按钮动作。
    func bindActions(arm: @escaping () -> Void, camera: @escaping () -> Void,
                     mode: @escaping () -> Void, altitude: @escaping () -> Void,
                     motion: @escaping () -> Void, pause: @escaping () -> Void,
                     reset: @escaping () -> Void) {
        armButton.onTap = arm
        cameraButton.onTap = camera
        modeButton.onTap = mode
        altitudeButton.onTap = altitude
        motionButton.onTap = motion
        pauseButton.onTap = pause
        resetButton.onTap = reset
    }

    /// 更新按钮标题（反映当前状态）。
    func setButtonTitles(armed: Bool, stabilized: Bool, altitudeHold: Bool,
                         motion: Bool, paused: Bool) {
        armButton.setTitle(armed ? "上锁" : "起飞")
        modeButton.setTitle(stabilized ? "自稳" : "手动")
        altitudeButton.setTitle(altitudeHold ? "定高" : "手动")
        motionButton.setTitle(motion ? "体感" : "摇杆")
        pauseButton.setTitle(paused ? "继续" : "暂停")
    }
}


// MARK: - 就绪标记

extension ControlOverlayView {
    /// 标记 App 已就绪（UI 测试用）。
    func markReady() {
        readyMarker.accessibilityValue = "ready"
    }
}
