import Foundation

// MARK: - 自稳控制器

/// 姿态控制器：把摇杆输入换算成**机体坐标系**的目标角速度。
///
/// 机体轴约定（与 `FlightState.angularVelocity` 一致）：
/// - `.x` 绕右轴 —— 正为抬头
/// - `.y` 绕上轴 —— 正为机头左转
/// - `.z` 绕后轴 —— 正为左滚
///
/// 摇杆约定（UI 侧，符合直觉）：roll 正 = 右滚，pitch 正 = 低头前进，yaw 正 = 机头右转。
/// 两者之间差一个负号，换算集中在本类型里做。
///
/// 两种模式：
/// - `.acro`：摇杆直接给目标角速度（手动，考验操控）。
/// - `.stabilized`：摇杆给**目标倾角**（Angle 模式），由角度环换算成角速度目标。
///   这两种的区别很关键：如果自稳也用角速度目标，推住杆会一路滚到翻，
///   因为回中项（增益 3.4）压不住杆量（4.2）。
public struct StabilizedController: Sendable {

    public enum Mode: Equatable, Sendable {
        /// 手动：摇杆 → 角速度目标。
        case acro
        /// 自稳：摇杆 → 目标倾角，再经角度环 → 角速度目标。
        case stabilized
    }

    public var mode: Mode
    /// 自稳模式的最大倾角（弧度）。约 32° —— 常见消费级无人机的限幅。
    public var maxTiltAngle: Float
    /// 角度环增益（1/s）：倾角误差 → 角速度目标。
    public var angleGain: Float
    /// Acro 模式下摇杆满舵对应的最大角速度（rad/s）。
    public var maxAngularRate: Float
    /// 偏航摇杆满舵对应的最大角速度（rad/s）。偏航一般比横滚/俯仰慢。
    public var maxYawRate: Float

    public init(mode: Mode = .stabilized,
                maxTiltAngle: Float = 0.56,
                angleGain: Float = 6.5,
                maxAngularRate: Float = 4.5,
                maxYawRate: Float = 2.6) {
        self.mode = mode
        self.maxTiltAngle = maxTiltAngle
        self.angleGain = angleGain
        self.maxAngularRate = maxAngularRate
        self.maxYawRate = maxYawRate
    }

    /// 由摇杆输入计算目标角速度（机体坐标系，rad/s）。
    public func targetAngularVelocity(input: ControlInput, state: FlightState) -> Vec3 {
        // 偏航两种模式都是角速度指令
        let yawRate = -clamp(input.yaw, -1, 1) * maxYawRate

        switch mode {
        case .acro:
            let pitchRate = -clamp(input.pitch, -1, 1) * maxAngularRate
            let rollRate = -clamp(input.roll, -1, 1) * maxAngularRate
            return Vec3(
                clamp(pitchRate, -maxAngularRate, maxAngularRate),
                clamp(yawRate, -maxYawRate, maxYawRate),
                clamp(rollRate, -maxAngularRate, maxAngularRate)
            )

        case .stabilized:
            let frame = BodyFrame(quaternion: state.attitude)

            // 当前姿态角（与 HUD 显示一致）
            // 俯仰：机体前轴高于地平线的角度，正为抬头
            let currentPitch = asin(clamp(frame.forward.y, -1, 1))
            // 横滚：正为右滚（右滚时 right.y 变负，所以取负号）
            let currentRoll = atan2(-frame.right.y, frame.up.y)

            // 摇杆 → 目标倾角。摇杆前推是「低头前进」，所以俯仰取负。
            let targetPitch = -clamp(input.pitch, -1, 1) * maxTiltAngle
            let targetRoll = clamp(input.roll, -1, 1) * maxTiltAngle

            // 角度环 → 角速度目标
            // 需要抬头（误差正）→ +x；需要左滚修正（误差使目标更「左」）→ +z
            let pitchRate = clamp((targetPitch - currentPitch) * angleGain,
                                  -maxAngularRate, maxAngularRate)
            let rollRate = clamp(-(targetRoll - currentRoll) * angleGain,
                                 -maxAngularRate, maxAngularRate)

            return Vec3(pitchRate, clamp(yawRate, -maxYawRate, maxYawRate), rollRate)
        }
    }
}

// MARK: - 高度保持

/// 高度保持控制器（PID）。
public struct AltitudeController: Sendable {
    public var kp: Float
    public var ki: Float
    public var kd: Float
    public var integral: Float
    public var targetAltitude: Float
    /// 推力输出限幅。
    public var outputMin: Float
    public var outputMax: Float
    /// 最大垂直速度。
    public var maxClimbRate: Float

    /// 悬停油门前馈：PID 只负责「相对悬停的修正量」，
    /// 这样积分项不用长距离爬升，响应也快得多。
    public var feedForward: Float

    public init(kp: Float = 0.62, ki: Float = 0.22, kd: Float = 0.18,
                targetAltitude: Float = 2.0, outputMin: Float = 0.0,
                outputMax: Float = 1.0, maxClimbRate: Float = 6.0,
                feedForward: Float = DroneSpec.hoverThrottle) {
        self.feedForward = feedForward
        self.kp = kp
        self.ki = ki
        self.kd = kd
        self.targetAltitude = targetAltitude
        self.outputMin = outputMin
        self.outputMax = outputMax
        self.maxClimbRate = maxClimbRate
        self.integral = 0
    }

    /// 计算油门指令（0...1）。
    public mutating func update(state: FlightState, dt: Float) -> Float {
        let error = targetAltitude - state.altitude
        let climbRate = state.velocity.y
        let derivative = (error - (targetAltitude - (state.altitude + climbRate * dt))) / max(dt, 1e-4)

        integral = clamp(integral + error * dt, -2, 2)
        let output = feedForward + kp * error + ki * integral + kd * derivative
        return clamp(output, outputMin, outputMax)
    }

    public mutating func reset() {
        integral = 0
    }
}

// MARK: - 飞行状态扩展

extension FlightState {
    /// 复位到待命状态。
    public mutating func reset(at position: Vec3 = Vec3(0, 0, 0)) {
        self = FlightState(position: position)
        initialHeading = 0
    }
}
