import Foundation

// MARK: - 机体参数

/// 无人机机型参数（以 FPV 竞速机为原型）。
public struct DroneSpec: Equatable, Sendable {
    /// 轴距（米），对角机臂间距。
    public var wheelbase: Float
    /// 整机质量（千克）。
    public var mass: Float
    /// 旋翼桨盘面积（平方米），用于推力估算。
    public var rotorArea: Float
    /// 桨距角（度）。
    public var bladePitch: Float
    /// 空气密度（千克/立方米）。
    public var airDensity: Float
    /// 桨叶阻力系数。
    public var bladeDragCoefficient: Float
    /// 机臂迎风面积（平方米）。
    public var frameArea: Float
    /// 机架阻力系数。
    public var frameDragCoefficient: Float
    /// 电机到机体质心的力臂（米）。
    public var armLength: Float
    /// 最大转速（弧度/秒）。
    public var maxRotorSpeed: Float
    /// 最小转速（弧度/秒），怠速。
    public var idleRotorSpeed: Float
    /// 电池能量（焦耳），用于功耗/续航估算。
    public var batteryEnergy: Float

    public init(
        wheelbase: Float = 0.235,
        mass: Float = 0.65,
        rotorArea: Float = 0.0058,
        bladePitch: Float = 4.7,
        airDensity: Float = 1.225,
        bladeDragCoefficient: Float = 0.025,
        frameArea: Float = 0.012,
        frameDragCoefficient: Float = 1.2,
        armLength: Float = 0.166,
        maxRotorSpeed: Float = 1250.0,
        idleRotorSpeed: Float = 22.0,
        batteryEnergy: Float = 22.0
    ) {
        self.wheelbase = wheelbase
        self.mass = mass
        self.rotorArea = rotorArea
        self.bladePitch = bladePitch
        self.airDensity = airDensity
        self.bladeDragCoefficient = bladeDragCoefficient
        self.frameArea = frameArea
        self.frameDragCoefficient = frameDragCoefficient
        self.armLength = armLength
        self.maxRotorSpeed = maxRotorSpeed

        // 怠速推力必须小于悬停推力，否则上锁时机体也会被顶起来。
        // 注意：这里不能用 self.thrustCoefficient（计算属性依赖尚未初始化的存储属性）。
        let coefficient = airDensity * rotorArea * (bladePitch * .pi / 180 * 1.6)
        let idleThrust = coefficient * idleRotorSpeed * idleRotorSpeed
        let hoverThrust = mass * 9.81 / 4
        self.idleRotorSpeed = idleThrust < hoverThrust ? idleRotorSpeed : 0
        self.batteryEnergy = batteryEnergy
    }

    /// 单旋翼在静止空气中的最大推力（牛顿）。
    public var maxThrustPerRotor: Float {
        // T = 2 * ρ * A * (v_blade)² * C_T 近似，用桨距角换算
        let ct = bladePitch * .pi / 180 * 1.6  // 经验推力系数
        return 2 * airDensity * rotorArea * (maxRotorSpeed * rotorArea * 0.5) * ct
    }

    /// 单旋翼推力系数（与 `FlightDynamics.thrust(forRotorSpeed:)` 保持一致）。
    public var thrustCoefficient: Float {
        airDensity * rotorArea * (bladePitch * .pi / 180 * 1.6)
    }

    /// 悬停所需的单旋翼转速（rad/s）。
    ///
    /// 必须和推力公式用同一个系数，否则算出来的转速对不上实际推力
    /// （之前这里和 thrust() 的公式不一致，导致怠速推力过大、把机顶上天）。
    public var hoverRotorSpeed: Float {
        let target = mass * 9.81 / 4
        let k = thrustCoefficient
        guard k > 0 else { return 0 }
        let speed = (target / k).squareRoot()
        return min(max(speed, 0), maxRotorSpeed)
    }

    /// 机臂推力/扭矩耦合系数：加速转速时额外产生的反扭矩。
    public var torqueCoupling: Float { bladePitch * .pi / 180 }

    /// 油门行程中「恰好悬停」的位置。
    ///
    /// 手动和定高模式共用同一条映射曲线：0 → 怠速，本值 → 悬停转速，1 → 满速。
    /// 定高控制器也以它作为前馈基准，否则控制器的输出区间会整体偏离悬停点。
    public static let hoverThrottle: Float = 0.42
}

/// 电机响应模型（时间常数 + 饱和）。
public struct MotorModel: Equatable, Sendable {
    /// 转速响应时间常数（秒），越小越跟手。
    public var timeConstant: Float
    /// 单电机最大推力（牛顿）。
    public var maxThrust: Float
    /// 反扭矩系数（N·m per 单位推力/转速比）。
    public var torqueConstant: Float

    public init(timeConstant: Float = 0.045, maxThrust: Float = 3.2, torqueConstant: Float = 0.018) {
        self.timeConstant = timeConstant
        self.maxThrust = maxThrust
        self.torqueConstant = torqueConstant
    }
}

// MARK: - 控制输入

/// 飞行控制器输入（归一化到 -1...1）。
public struct ControlInput: Equatable, Sendable {
    /// 油门（0 = 怠速/降落，1 = 最大）。
    public var throttle: Float
    /// 横滚（左右倾斜），正为右。
    public var roll: Float
    /// 俯仰（前后倾斜），正为前。
    public var pitch: Float
    /// 偏航（机头转动），正为右。
    public var yaw: Float
    /// 手动/自动高度模式。
    public var altitudeMode: AltitudeMode

    public init(throttle: Float = 0, roll: Float = 0, pitch: Float = 0, yaw: Float = 0,
                altitudeMode: AltitudeMode = .manual) {
        self.throttle = throttle
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
        self.altitudeMode = altitudeMode
    }

    public static let neutral = ControlInput()
}

/// 高度控制模式。
public enum AltitudeMode: Equatable, Sendable {
    /// 手动油门。
    case manual
    /// 自动定高（当前高度为目标）。
    case hold(altitude: Float)
}

/// 飞行模式。
public enum FlightMode: Equatable, Sendable {
    /// 停机（电机停转）。
    case disarmed
    /// 怠速悬停（自稳）。
    case stabilized
    /// 手动（无自稳，速度与姿态直接由摇杆决定）。
    case manual
    /// 失控保护——已翻转或坠机。
    case crashed
}

// MARK: - 飞行状态

/// 完整飞行状态。
public struct FlightState: Equatable, Sendable {
    /// 世界位置。
    public var position: Vec3
    /// 世界速度（米/秒）。
    public var velocity: Vec3
    /// 姿态。
    public var attitude: Quat
    /// 机体角速度（rad/s，机体系）。
    public var angularVelocity: Vec3
    /// 四个电机转速（rad/s），顺序：前右、前左、后左、后右。
    public var motorSpeeds: [Float]
    /// 累计耗电（焦耳）。
    public var energyUsed: Float
    /// 飞行模式。
    public var mode: FlightMode
    /// 是否触地。
    public var onGround: Bool
    /// 上一次碰撞的法向与冲击强度。
    public var lastImpactNormal: Vec3
    public var lastImpactSpeed: Float
    /// 归一化的推力余量（0 = 满推力无法再加速，1 = 无推力）。
    public var thrustHeadroom: Float
    /// 初始航向（起飞时的机头朝向，用于偏航回中）。
    public var initialHeading: Float

    public init(
        position: Vec3 = Vec3(0, 0, 0),
        velocity: Vec3 = Vec3(0, 0, 0),
        attitude: Quat = .identity,
        angularVelocity: Vec3 = Vec3(0, 0, 0),
        motorSpeeds: [Float] = [0, 0, 0, 0],
        energyUsed: Float = 0,
        mode: FlightMode = .disarmed,
        onGround: Bool = true,
        lastImpactNormal: Vec3 = Vec3(0, 1, 0),
        lastImpactSpeed: Float = 0,
        thrustHeadroom: Float = 1,
        initialHeading: Float = 0
    ) {
        self.position = position
        self.velocity = velocity
        self.attitude = attitude
        self.angularVelocity = angularVelocity
        self.motorSpeeds = motorSpeeds
        self.energyUsed = energyUsed
        self.mode = mode
        self.onGround = onGround
        self.lastImpactNormal = lastImpactNormal
        self.lastImpactSpeed = lastImpactSpeed
        self.thrustHeadroom = thrustHeadroom
        self.initialHeading = initialHeading
    }

    /// 空速（米/秒）。
    public var airspeed: Float { velocity.length }

    /// 地速（米/秒）。
    public var groundSpeed: Float { Vec3(velocity.x, 0, velocity.z).length }

    /// 高度（米）。
    public var altitude: Float { position.y }

    /// 剩余电量比例（0...1）。
    public func batteryFraction(spec: DroneSpec) -> Float {
        clamp(1 - energyUsed / spec.batteryEnergy, 0, 1)
    }
}

// MARK: - 环境

/// 环境条件。
public struct Environment: Equatable, Sendable {
    /// 风速（世界坐标，米/秒）。
    public var wind: Vec3
    /// 湍流强度（0...1）。
    public var turbulence: Float
    /// 重力加速度。
    public var gravity: Float
    /// 地面高度（米）。
    public var groundHeight: Float

    public init(wind: Vec3 = Vec3(0, 0, 0), turbulence: Float = 0.06,
                gravity: Float = 9.81, groundHeight: Float = 0) {
        self.wind = wind
        self.turbulence = turbulence
        self.gravity = gravity
        self.groundHeight = groundHeight
    }

    public static let calm = Environment()
}
