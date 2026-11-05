import Foundation
import UIKit
import CoreMotion

// MARK: - 虚拟摇杆

/// 虚拟摇杆：底座常驻可见，触摸时拇指跟随，松手回中。
///
/// 设计要点（第一版做成「按下才画」，玩家看不到摇杆在哪，等于没有反馈）：
/// - 底座圆环始终显示，位置固定在视图中心；
/// - 触摸落在视图内任意位置都能操作，拇指按偏移量移动；
/// - 拖动超出半径时拇指停在边缘，明确表示已到极限；
/// - 拖动时底座高亮，松手恢复，给一个清楚的「已接管」反馈。
final class VirtualJoystick: UIView {

    /// 归一化输出 (-1...1)，x 向右为正，y 向上为正。
    private(set) var value: CGPoint = .zero
    /// 是否正在被拖动。
    private(set) var isActive = false

    /// 摇杆可拖动的半径（像素）。
    var radius: CGFloat = 78
    /// 死区（0...1）。
    var deadzone: CGFloat = 0.12
    /// 是否是左半屏的摇杆。
    var isLeftStick = true

    /// 拖动开始/结束时回调（用于震动反馈）。
    var onEngage: (() -> Void)?
    var onRelease: (() -> Void)?

    private weak var trackedTouch: UITouch?
    private var stickCenter: CGPoint = .zero

    private let baseFill = CAShapeLayer()
    private let baseRing = CAShapeLayer()
    private let crosshair = CAShapeLayer()
    private let knob = CAShapeLayer()

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
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = false

        // 底座：半透明填充 + 亮边，保证在明亮天空和暗色地面上都看得清
        baseFill.fillColor = UIColor.black.withAlphaComponent(0.20).cgColor
        baseRing.fillColor = nil
        baseRing.strokeColor = UIColor.white.withAlphaComponent(0.55).cgColor
        baseRing.lineWidth = 2

        crosshair.fillColor = nil
        crosshair.strokeColor = UIColor.white.withAlphaComponent(0.22).cgColor
        crosshair.lineWidth = 1

        knob.fillColor = UIColor.white.withAlphaComponent(0.44).cgColor
        knob.strokeColor = UIColor.white.withAlphaComponent(0.95).cgColor
        knob.lineWidth = 2

        layer.addSublayer(baseFill)
        layer.addSublayer(crosshair)
        layer.addSublayer(baseRing)
        layer.addSublayer(knob)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stickCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        // 底座直径不超过视图短边的 80%，避免贴边或溢出
        radius = min(radius, min(bounds.width, bounds.height) * 0.4)
        redrawBase(highlighted: isActive)
        redrawKnob()
    }

    // MARK: 绘制

    private func redrawBase(highlighted: Bool) {
        baseFill.path = UIBezierPath(arcCenter: stickCenter, radius: radius,
                                     startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath
        baseRing.path = baseFill.path
        baseRing.strokeColor = UIColor.white
            .withAlphaComponent(highlighted ? 0.95 : 0.55).cgColor
        baseFill.fillColor = UIColor.black
            .withAlphaComponent(highlighted ? 0.32 : 0.20).cgColor

        // 十字准线，帮助判断回中
        let path = UIBezierPath()
        path.move(to: CGPoint(x: stickCenter.x - radius, y: stickCenter.y))
        path.addLine(to: CGPoint(x: stickCenter.x + radius, y: stickCenter.y))
        path.move(to: CGPoint(x: stickCenter.x, y: stickCenter.y - radius))
        path.addLine(to: CGPoint(x: stickCenter.x, y: stickCenter.y + radius))
        crosshair.path = path.cgPath
    }

    private func redrawKnob() {
        let knobRadius = radius * 0.36
        let knobCenter = CGPoint(
            x: stickCenter.x + value.x * (radius - knobRadius),
            y: stickCenter.y - value.y * (radius - knobRadius)
        )
        knob.path = UIBezierPath(arcCenter: knobCenter, radius: knobRadius,
                                 startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath
    }

    // MARK: 触摸

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first, trackedTouch == nil else { return }
        trackedTouch = touch
        isActive = true
        redrawBase(highlighted: true)
        updateValue(for: touch)
        onEngage?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first,
              let tracked = trackedTouch,
              touch === tracked else { return }
        updateValue(for: touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        releaseIfTracked(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        releaseIfTracked(touches)
    }

    private func releaseIfTracked(_ touches: Set<UITouch>) {
        guard let tracked = trackedTouch,
              touches.contains(where: { $0 === tracked }) else { return }
        trackedTouch = nil
        isActive = false
        value = .zero
        redrawBase(highlighted: false)
        redrawKnob()
        onRelease?()
    }

    private func updateValue(for touch: UITouch) {
        let p = touch.location(in: self)
        let dx = p.x - stickCenter.x
        let dy = p.y - stickCenter.y
        let distance = (dx * dx + dy * dy).squareRoot()

        guard distance > 1 else {
            value = .zero
            redrawKnob()
            return
        }

        let normalized = min(distance / radius, 1)
        let magnitude = normalized <= deadzone ? 0 : (normalized - deadzone) / (1 - deadzone)
        value = CGPoint(x: (dx / distance) * magnitude, y: (-dy / distance) * magnitude)
        redrawKnob()
    }

    /// 取某个轴的输出。
    /// - Parameter index: 0 = 水平，1 = 垂直（向上为正）
    func axis(_ index: Int) -> Float {
        index == 0 ? Float(value.x) : Float(value.y)
    }
}

// MARK: - 飞行输入管理器

/// 把屏幕触摸、设备姿态映射为飞行控制输入。
final class FlightInputController {

    /// 左摇杆：油门 + 偏航。
    let throttleStick = VirtualJoystick()
    /// 右摇杆：横滚 + 俯仰。
    let attitudeStick = VirtualJoystick()

    private let motionManager = CMMotionManager()
    private(set) var motionEnabled = false
    private var referenceAttitude: CMAttitude?

    /// 当前输入。
    private(set) var input = ControlInput.neutral
    /// 上次的油门值（油门是增量式的，向上推加速）。
    private var lastThrottle: Float = 0

    /// 是否使用体感模式（替换右摇杆）。
    var useMotion = false

    init() {
        throttleStick.radius = 105
        attitudeStick.radius = 105
    }

    /// 启动陀螺仪。
    func startMotion() {
        guard motionManager.isDeviceMotionAvailable, !motionEnabled else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            if self.referenceAttitude == nil {
                self.referenceAttitude = motion.attitude
            }
        }
        motionEnabled = true
    }

    func stopMotion() {
        motionManager.stopDeviceMotionUpdates()
        motionEnabled = false
        referenceAttitude = nil
    }

    /// 把当前姿态重设为「水平」参考。
    func resetMotionReference() {
        referenceAttitude = nil
    }

    /// 重新计算控制输入。
    func updateInput(altitudeMode: AltitudeMode) {
        var newInput = ControlInput()
        newInput.altitudeMode = altitudeMode

        // 左摇杆：X = 偏航，Y = 油门
        newInput.yaw = throttleStick.axis(0)
        let throttleAxis = throttleStick.axis(1)

        if case .manual = altitudeMode {
            // 油门是增量式的：向上推加速，向下推减速（像真机的油门杆）
            lastThrottle = clamp(lastThrottle + throttleAxis * 0.025, 0, 1)
            newInput.throttle = lastThrottle
        } else {
            newInput.throttle = 0
        }

        if useMotion && motionEnabled {
            // 体感：用设备俯仰/横滚代替右摇杆
            if let motion = motionManager.deviceMotion {
                let pitch = motion.attitude.pitch - (referenceAttitude?.pitch ?? 0)
                let roll = motion.attitude.roll - (referenceAttitude?.roll ?? 0)
                // 陀螺仪读数是 Double，用 Swift 原生的 min/max 限幅
                newInput.pitch = Float(min(max(pitch / 0.45, -1), 1))
                newInput.roll = Float(min(max(roll / 0.45, -1), 1))
            }
        } else {
            newInput.roll = attitudeStick.axis(0)
            newInput.pitch = attitudeStick.axis(1)
        }

        input = newInput
    }

    /// 重置油门。
    func resetThrottle(to value: Float = 0) {
        lastThrottle = clamp(value, 0, 1)
    }
}
