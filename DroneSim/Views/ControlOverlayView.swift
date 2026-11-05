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

        // 摇杆：固定在底部两角，常驻可见。
        // 视图比底座大一圈，留出手指的活动余量。
        leftStick.isLeftStick = true
        rightStick.isLeftStick = false
        leftStick.isAccessibilityElement = false
        rightStick.isAccessibilityElement = false
        leftStick.accessibilityElementsHidden = true
        rightStick.accessibilityElementsHidden = true
        leftStick.translatesAutoresizingMaskIntoConstraints = false
        rightStick.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftStick)
        addSubview(rightStick)
        NSLayoutConstraint.activate([
            leftStick.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            leftStick.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            leftStick.widthAnchor.constraint(equalToConstant: 230),
            leftStick.heightAnchor.constraint(equalToConstant: 230),

            rightStick.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rightStick.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            rightStick.widthAnchor.constraint(equalToConstant: 230),
            rightStick.heightAnchor.constraint(equalToConstant: 230),
        ])

        // 摇杆的拖动反馈（轻微震动）
        leftStick.onEngage = { Haptics.impact(.light) }
        rightStick.onEngage = { Haptics.impact(.light) }

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

        // 按钮：顶部横向一排。
        // 竖排会超出横屏高度（7 个 × 61pt = 427pt，可用高度只有约 390pt），
        // 排在顶部横着放才放得下，也不和底部摇杆抢空间。
        let buttons = [armButton, cameraButton, modeButton, altitudeButton,
                       motionButton, pauseButton, resetButton]
        let identifiers = ["button.arm", "button.camera", "button.mode", "button.altitude",
                           "button.motion", "button.pause", "button.reset"]
        for (button, identifier) in zip(buttons, identifiers) {
            button.setIdentifier(identifier)
        }

        let row = UIStackView(arrangedSubviews: buttons)
        row.axis = .horizontal
        row.spacing = 7
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14),
        ])
        for button in buttons {
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 46),
                button.heightAnchor.constraint(equalToConstant: 46),
            ])
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
