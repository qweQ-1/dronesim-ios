import Foundation
import UIKit
import CoreMotion

// MARK: - 虚拟摇杆

/// 虚拟摇杆：既是输入源，也是可见控件。
final class VirtualJoystick: UIView {

    /// 归一化输出 (-1...1)，x 向右为正，y 向上为正。
    private(set) var value: CGPoint = .zero
    /// 是否正在被拖动。
    private(set) var isActive = false

    /// 摇杆半径（像素）。
    var radius: CGFloat = 110
    /// 死区（0...1）。
    var deadzone: CGFloat = 0.10

    /// 归属的触摸对象。
    private weak var trackedTouch: UITouch?
    /// 摇杆原点（该 view 坐标系）。
    private var origin: CGPoint = .zero

    private let baseCircle = CAShapeLayer()
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
        // 摇杆自己接收触摸：区域是屏幕下半部分的固定矩形，
        // 命中测试按「离摇杆中心最近的半边」分配，避免两个摇杆互相抢。
        isUserInteractionEnabled = true

        baseCircle.fillColor = UIColor.black.withAlphaComponent(0.22).cgColor
        baseCircle.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        baseCircle.lineWidth = 1.5
        baseCircle.opacity = 0
        layer.addSublayer(baseCircle)

        knob.fillColor = UIColor.white.withAlphaComponent(0.45).cgColor
        knob.strokeColor = UIColor.white.withAlphaComponent(0.8).cgColor
        knob.lineWidth = 1.5
        knob.opacity = 0
        layer.addSublayer(knob)
    }

    /// 触摸开始。`point` 是该 view 坐标系下的位置。
    func begin(touch: UITouch, at point: CGPoint) {
        trackedTouch = touch
        isActive = true
        origin = point
        value = .zero

        baseCircle.opacity = 1
        knob.opacity = 1
        redraw(center: point, knobCenter: point)
    }

    /// 触摸移动。
    func move(to point: CGPoint) {
        guard isActive else { return }
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > 0.5 else {
            value = .zero
            redraw(center: origin, knobCenter: origin)
            return
        }
        let normalized = min(distance / radius, 1)
        let magnitude = normalized <= deadzone ? 0 : (normalized - deadzone) / (1 - deadzone)
        value = CGPoint(x: (dx / distance) * magnitude, y: (-dy / distance) * magnitude)

        // 拇指方向与实际位移一致（限制在半径内）
        let knobCenter = CGPoint(
            x: origin.x + (dx / distance) * min(distance, radius),
            y: origin.y + (dy / distance) * min(distance, radius)
        )
        redraw(center: origin, knobCenter: knobCenter)
    }

    /// 触摸结束。
    func end() {
        trackedTouch = nil
        isActive = false
        value = .zero
        baseCircle.opacity = 0
        knob.opacity = 0
    }

    private func redraw(center: CGPoint, knobCenter: CGPoint) {
        // 视图可能比屏幕小，摇杆超出部分裁掉
        baseCircle.path = UIBezierPath(arcCenter: center, radius: radius,
                                       startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath
        knob.path = UIBezierPath(arcCenter: knobCenter, radius: radius * 0.34,
                                 startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath
    }

    /// 取某个轴的输出。
    /// - Parameter index: 0 = 水平，1 = 垂直（向上为正）
    func axis(_ index: Int) -> Float {
        index == 0 ? Float(value.x) : Float(value.y)
    }

    // MARK: 触摸

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // 只有按下点在「离本摇杆中心更近」的那半屏才响应
        guard let window else { return false }
        let screenPoint = convert(point, to: window)
        let midX = window.bounds.midX
        return screenPoint.x < midX ? isLeftStick : !isLeftStick
    }

    /// 是否是左半屏的摇杆（左半屏归属左摇杆）。
    var isLeftStick: Bool = true

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        begin(touch: touch, at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first else { return }
        move(to: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        end()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        end()
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
