import Foundation

// MARK: - 飞行动力学

/// 四旋翼飞行动力学求解器。
///
/// 模型要点：
/// - 四个电机各自产生沿机体 +Y 方向的推力和绕机体 Y 轴的反扭矩；
/// - 电调有响应延迟（时间常数），这让飞行手感有「黏性」，是拟真感的关键之一；
/// - 气阻力同时包含机架阻力（与相对风速平方成正比）和旋翼下洗阻力；
/// - 角加速度由力矩与转动惯量决定，角速度有轴承阻尼；
/// - 姿态积分用四元数，角速度在机体系。
///
/// 该类型是纯值类型、无 UIKit/Metal 依赖，便于用逻辑测试覆盖。
public struct FlightDynamics: Sendable {
    /// 固定积分步长（秒）。渲染帧率与物理解耦，物理永远稳定。
    public static let fixedTimeStep: Float = 1.0 / 240.0

    public var spec: DroneSpec
    public var motor: MotorModel
    /// 转动惯量（机体系，kg·m²）。
    public var inertia: Vec3
    /// 角阻尼系数（每单位角速度的力矩）。
    public var angularDamping: Float
    /// 地面碰撞恢复系数。
    public var restitution: Float
    /// 地面摩擦系数。
    public var groundFriction: Float

    public init(spec: DroneSpec = DroneSpec(), motor: MotorModel = MotorModel()) {
        self.spec = spec
        self.motor = motor
        // 典型 5 寸 FPV 机的转动惯量量级。
        self.inertia = Vec3(0.0042, 0.0075, 0.0042)
        self.angularDamping = 0.0035
        self.restitution = 0.18
        self.groundFriction = 0.85
    }

    /// 电机布局：0=前右, 1=前左, 2=后左, 3=后右。
    /// 每个电机的机体系位置偏移（米）与旋转方向（+1 逆时针 / -1 顺时针）。
    public static let motorLayout: [(offset: Vec3, spin: Float)] = [
        (Vec3(0.083, 0, -0.083), -1),
        (Vec3(-0.083, 0, -0.083), +1),
        (Vec3(-0.083, 0, 0.083), +1),
        (Vec3(0.083, 0, 0.083), -1),
    ]

    /// 推进器命令到各电机转速（rad/s）。
    /// - 总推力由油门决定；
    /// - 横滚由右/左电机差动；
    /// - 俯仰由前/后电机差动；
    /// - 偏航由对角线差动。
    public func commandedRotorSpeeds(input: ControlInput, state: FlightState) -> [Float] {
        let spec = self.spec
        let idle = spec.idleRotorSpeed
        let hover = spec.hoverRotorSpeed
        let maxS = spec.maxRotorSpeed

        // 总推力映射：油门 0 → 怠速；油门 1 → 满推力。悬停点大约在 0.42 油门附近，
        // 这里用分段线性，让低油门段更细腻（跟真机一样，怠速到悬停需要一点油门行程）。
        var base: Float
        switch input.altitudeMode {
        case .manual:
            // 油门 0 → 怠速（几乎无推力），悬停点 → hoverRotorSpeed，1 → 满速。
            // 悬停点在油门行程中的位置由真实转速反推，保证「给到悬停油门就能悬停」。
            let t = clamp(input.throttle, 0, 1)
            let hoverThrottle: Float = 0.42
            if t < hoverThrottle {
                base = lerp(idle, hover, t / hoverThrottle)
            } else {
                base = lerp(hover, maxS, (t - hoverThrottle) / (1 - hoverThrottle))
            }
        case .hold:
            // 定高模式：油门由高度控制器给出（外部已算好，throttle 字段直接是推力指令）。
            base = lerp(idle, maxS, clamp(input.throttle, 0, 1))
        }

        // 差动幅度：随总推力增大而增大（大油门时姿态控制更"硬"）。
        let authority = clamp((base - idle) / max(hover - idle, 1), 0, 1)
        let mixRange = (maxS - idle) * 0.55 * (0.35 + 0.65 * authority)

        let rollCmd = clamp(input.roll, -1, 1) * mixRange
        let pitchCmd = clamp(input.pitch, -1, 1) * mixRange
        let yawCmd = clamp(input.yaw, -1, 1) * mixRange

        // 布局：0 FR, 1 FL, 2 RL, 3 RR
        // 横滚（右倾）→ 右侧电机加速、左侧减速：FR+, RR+, FL-, RL-
        // 俯仰（低头前进）→ 前电机加速、后电机减速：FR+, FL+, RL-, RR-
        // 偏航（机头右转）→ 逆时针电机加速：FL+, RL+, FR-, RR-（+1 为逆时针）
        var speeds = [Float](repeating: base, count: 4)
        speeds[0] += rollCmd + pitchCmd - yawCmd
        speeds[1] += -rollCmd + pitchCmd + yawCmd
        speeds[2] += -rollCmd - pitchCmd + yawCmd
        speeds[3] += rollCmd - pitchCmd - yawCmd

        for i in speeds.indices {
            speeds[i] = clamp(speeds[i], 0, maxS)
        }
        return speeds
    }

    /// 推力曲线：转速 → 推力（牛顿）。二次律，附带轻微的饱和。
    ///
    /// 系数必须与 `DroneSpec.thrustCoefficient` 一致，
    /// 否则悬停转速算出来对不上实际推力。
    public func thrust(forRotorSpeed omega: Float) -> Float {
        let nominal = self.spec.thrustCoefficient * omega * omega
        return min(nominal, self.motor.maxThrust)
    }

    /// 推进一步物理仿真。
    public mutating func step(state: inout FlightState, input: ControlInput,
                              environment: Environment, dt: Float) {
        guard state.mode != .crashed else { return }

        let spec = self.spec
        let commands = commandedRotorSpeeds(input: input, state: state)

        // --- 电机响应（一阶惯性）---
        var actualSpeeds = state.motorSpeeds
        if actualSpeeds.count != 4 { actualSpeeds = [0, 0, 0, 0] }
        let alpha = clamp(dt / max(motor.timeConstant, 1e-4), 0, 1)
        for i in 0..<4 {
            actualSpeeds[i] += (commands[i] - actualSpeeds[i]) * alpha
        }
        state.motorSpeeds = actualSpeeds

        // --- 相对气流 ---
        let windAtPos = environment.wind + turbulence(environment: environment,
                                                      time: state.energyUsed,
                                                      position: state.position)
        let relativeAir = state.velocity - windAtPos
        let airspeed = relativeAir.length

        // --- 推力合成 ---
        var thrustBody = Vec3(0, 0, 0)
        var torqueBody = Vec3(0, 0, 0)
        var totalThrust: Float = 0

        for i in 0..<4 {
            let layout = Self.motorLayout[i]
            let omega = actualSpeeds[i]
            let t = thrust(forRotorSpeed: omega)
            totalThrust += t

            // 推力沿机体 +Y
            thrustBody.y += t

            // 反扭矩：与旋翼旋转方向相反
            let dragTorque = t * motor.torqueConstant * layout.spin * -1
            torqueBody.y += dragTorque

            // 力矩：r × F，r 为电机位置（机体系），F 沿 +Y
            let r = layout.offset
            torqueBody += r.cross(Vec3(0, t, 0))

            // 桨叶阻力（机体系，沿相对气流反方向，简化到机体轴）
            if airspeed > 0.01 {
                let bladeDrag = spec.bladeDragCoefficient * spec.rotorArea * airspeed * airspeed
                let dir = state.attitude.toBody(-relativeAir).normalized
                torqueBody += Vec3(dir.x * bladeDrag * 0.02, 0, dir.z * bladeDrag * 0.02)
            }
        }

        // 机架阻力：相对风速平方，作用在机体轴上
        let frameDragMag = 0.5 * spec.airDensity * spec.frameArea *
            spec.frameDragCoefficient * airspeed * airspeed
        if airspeed > 0.01 {
            let dragDirBody = state.attitude.toBody(-relativeAir).normalized
            let dragBody = dragDirBody * frameDragMag
            thrustBody += dragBody
        }

        // 下洗阻力：旋翼把空气往下推，机体受到向上的反作用；前进时表现为阻力
        thrustBody.y += totalThrust * 0.02

        // 角阻尼
        torqueBody -= state.angularVelocity * self.angularDamping

        // --- 线运动（世界系）---
        //
        // 注意量纲：thrustWorld 是力（牛顿），要除以质量才是加速度；
        // gravity 已经是加速度（m/s²），不能再除以质量。
        // 之前把两者一起除以质量，等于把重力放大成 15.09 m/s²，
        // 结果推力正好等于重力时无人机仍在加速下坠。
        let thrustWorld = state.attitude.toWorld(thrustBody)
        let thrustAcceleration = thrustWorld / spec.mass
        let gravityAcceleration = Vec3(0, -environment.gravity, 0)
        let acceleration = thrustAcceleration + gravityAcceleration
        state.velocity += acceleration * dt
        state.position += state.velocity * dt

        // --- 角运动（机体系）---
        let angularAccel = Vec3(
            torqueBody.x / inertia.x,
            torqueBody.y / inertia.y,
            torqueBody.z / inertia.z
        )
        state.angularVelocity += angularAccel * dt
        state.attitude = state.attitude.integrated(byBodyAngularVelocity: state.angularVelocity, dt: dt)

        // --- 能量消耗：推力功率 + 姿态控制功率 ---
        let power = totalThrust * 9.81 / 22.0 * 0.55 + state.angularVelocity.length * 0.4
        state.energyUsed += power * dt

        // --- 地面碰撞 ---
        handleGroundCollision(state: &state, environment: environment)

        // --- 推力余量 ---
        let maxTotal = motor.maxThrust * 4
        state.thrustHeadroom = clamp(1 - totalThrust / max(maxTotal, 0.001), 0, 1)

        // --- 失控判定 ---
        let upDot = state.attitude.up.y
        if upDot < -0.2 {
            state.mode = .crashed
            state.angularVelocity = Vec3(0, 0, 0)
        }
    }

    /// 地面/障碍物碰撞处理。
    mutating func handleGroundCollision(state: inout FlightState, environment: Environment) {
        let ground = environment.groundHeight
        guard state.position.y <= ground else {
            state.onGround = false
            return
        }

        state.onGround = true
        state.position.y = ground
        // 法向反弹
        let normal = Vec3(0, 1, 0)
        let vn = state.velocity * normal
        if vn < 0 {
            state.lastImpactNormal = normal
            state.lastImpactSpeed = -vn
            state.velocity = state.velocity - normal * (vn * (1 + restitution))
            // 切向摩擦
            let tangent = state.velocity - normal * (state.velocity * normal)
            state.velocity = state.velocity - tangent * groundFriction
        }
        // 落地时姿态迅速拉平（真机落地会翻倒，这里做一个温和的恢复）
        state.angularVelocity = state.angularVelocity * 0.82
    }

    /// 湍流噪声（确定性的伪随机，避免用随机数导致不可复现）。
    private func turbulence(environment: Environment, time: Float, position: Vec3) -> Vec3 {
        guard environment.turbulence > 0 else { return .zero }
        let t = time
        let px = position.x * 0.35, py = position.y * 0.35, pz = position.z * 0.35
        let s = environment.turbulence
        return Vec3(
            sin(t * 1.7 + px * 0.9) * cos(t * 0.83 + pz * 1.1),
            sin(t * 1.31 + py * 1.4 + 0.7) * 0.6,
            cos(t * 1.11 + pz * 0.7 + 1.3) * sin(t * 0.91 + px * 0.6)
        ) * s * 2.2
    }
}
