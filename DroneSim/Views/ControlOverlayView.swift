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
        addSubview(leftStick)
        addSubview(rightStick)

        NSLayoutConstraint.activate([
            leftStick.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
            leftStick.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 24),
            leftStick.widthAnchor.constraint(equalToConstant: 150),
            leftStick.heightAnchor.constraint(equalToConstant: 150),

            rightStick.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
            rightStick.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -24),
            rightStick.widthAnchor.constraint(equalToConstant: 150),
            rightStick.heightAnchor.constraint(equalToConstant: 150),
        ])

        // 按钮组：右侧竖排
        let buttons = [armButton, cameraButton, modeButton, altitudeButton,
                       motionButton, pauseButton, resetButton]
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
