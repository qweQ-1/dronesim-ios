import Foundation

// MARK: - 自稳控制器

/// 飞控自稳模式（Acro / 手动 + 增稳）。
///
/// 手动模式下摇杆控制的是**角加速度**而不是角速度，真机上就是这样：
/// 松杆后无人机会保持当前姿态角速度继续旋转，除非有自稳增益把它拉回水平。
/// 这里提供两种模式：
/// - `.acro`：纯手动，角速度直接由摇杆给出（考验操控）。
/// - `.stabilized`：角速度由摇杆给出，同时有回中增益把姿态拉回水平（新手友好）。
public struct StabilizedController: Sendable {
    public enum Mode: Equatable, Sendable {
        /// 纯手动：摇杆 → 角速度目标。
        case acro
        /// 自稳：角速度目标 = 摇杆 + 姿态回中项。
        case stabilized
    }

    public var mode: Mode
    /// 姿态回中增益（1/s）。
    public var attitudeGain: Float
    /// 偏航回中增益（1/s）。
    public var yawReturnGain: Float
    /// 最大角速度（rad/s）。
    public var maxAngularRate: Float
    /// 摇杆到角速度的最大比例。
    public var rateAuthority: Float

    public init(mode: Mode = .stabilized, attitudeGain: Float = 3.4,
                yawReturnGain: Float = 0.0, maxAngularRate: Float = 6.5,
                rateAuthority: Float = 4.2) {
        self.mode = mode
        self.attitudeGain = attitudeGain
        self.yawReturnGain = yawReturnGain
        self.maxAngularRate = maxAngularRate
        self.rateAuthority = rateAuthority
    }

    /// 由摇杆输入计算目标角速度（机体系，rad/s）。
    public func targetAngularVelocity(input: ControlInput, state: FlightState) -> Vec3 {
        let roll = clamp(input.roll, -1, 1) * rateAuthority
        let pitch = clamp(input.pitch, -1, 1) * rateAuthority
        let yaw = clamp(input.yaw, -1, 1) * rateAuthority

        switch mode {
        case .acro:
            return Vec3(
                clamp(roll, -maxAngularRate, maxAngularRate),
                clamp(yaw, -maxAngularRate, maxAngularRate),
                clamp(pitch, -maxAngularRate, maxAngularRate)
            )
        case .stabilized:
            // 姿态回中：把当前姿态与目标（水平）的误差折算成角速度修正。
            // 用机体右/前轴在世界中的水平程度作为误差量。
            let frame = BodyFrame(quaternion: state.attitude)
            // 期望：机体 up 指向世界 up，机体 forward 保持航向（只回滚俯仰）
            let upError = Vec3(0, 1, 0) - frame.up
            let rightAxis = frame.right
            let forwardAxis = frame.forward
            let rollCorrection = (upError * rightAxis) * attitudeGain
            let pitchCorrection = (upError * forwardAxis) * attitudeGain

            // 偏航回中（可选）：把机头航向拉回初始航向
            var yawCorrection: Float = 0
            if yawReturnGain > 0 {
                let heading = atan2(frame.forward.x, -frame.forward.z)
                let targetHeading = state.initialHeading
                let delta = normalizeAngle(targetHeading - heading)
                yawCorrection = delta * yawReturnGain
            }

            return Vec3(
                clamp(roll + rollCorrection, -maxAngularRate, maxAngularRate),
                clamp(yaw + yawCorrection, -maxAngularRate, maxAngularRate),
                clamp(pitch + pitchCorrection, -maxAngularRate, maxAngularRate)
            )
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

    public init(kp: Float = 0.62, ki: Float = 0.22, kd: Float = 0.18,
                targetAltitude: Float = 2.0, outputMin: Float = 0.30,
                outputMax: Float = 1.0, maxClimbRate: Float = 6.0) {
        self.kp = kp
        self.ki = ki
        self.kd = kd
        self.targetAltitude = targetAltitude
        self.outputMin = outputMin
        self.outputMax = outputMax
        self.maxClimbRate = maxClimbRate
    }

    /// 计算油门指令（0...1）。
    public mutating func update(state: FlightState, dt: Float) -> Float {
        let error = targetAltitude - state.altitude
        let climbRate = state.velocity.y
        let derivative = (error - (targetAltitude - (state.altitude + climbRate * dt))) / max(dt, 1e-4)

        integral = clamp(integral + error * dt, -2, 2)
        let output = kp * error + ki * integral + kd * derivative
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
