import Foundation

// MARK: - 飞行管理器

/// 飞行管理器：把物理、自稳控制器、定高控制器和状态机串起来。
///
/// 时间管理采用**固定步长累加器**：
/// - 渲染帧率可以是 60/120Hz，物理永远以 240Hz 推进 → 帧率波动不影响手感；
/// - 每帧最多补算若干步，避免卡顿后「死亡螺旋」。
public final class FlightManager: @unchecked Sendable {
    public var dynamics: FlightDynamics
    public var state: FlightState
    public var environment: Environment
    public var stabilized: StabilizedController
    public var altitude: AltitudeController

    /// 物理累加器。
    private var accumulator: Float = 0
    /// 上一次物理推进后的时间戳。
    private var lastTimestamp: Float = 0
    /// 最近一次 update 收到的时间戳。
    public private(set) var lastUpdateTimestamp: Float = 0
    /// 上一帧实际推进的物理步数（用于性能监控）。
    public private(set) var lastStepCount: Int = 0
    /// 上一次物理推进消耗的秒数。
    public private(set) var lastPhysicsDuration: Float = 0

    /// 自稳模式开关（对应 UI 上的 Acro / 自稳）。
    public var stabilizedEnabled: Bool = true {
        didSet {
            stabilized.mode = stabilizedEnabled ? .stabilized : .acro
        }
    }

    /// 当前输入（由控制器写入）。
    public var input = ControlInput.neutral

    /// 起飞/降落回调，用于触发音效与状态提示。
    public var onArmedChange: ((Bool) -> Void)?
    public var onCrash: ((Float) -> Void)?

    public init(dynamics: FlightDynamics = FlightDynamics(),
                environment: Environment = .calm,
                state: FlightState = FlightState()) {
        self.dynamics = dynamics
        self.environment = environment
        self.state = state
        self.stabilized = StabilizedController()
        self.altitude = AltitudeController()
    }

    /// 是否已解锁（电机转动）。
    public var isArmed: Bool { state.mode != .disarmed && state.mode != .crashed }

    /// 解锁电机，进入自稳悬停。
    public func arm() {
        guard state.mode == .disarmed else { return }
        state.mode = .stabilized
        altitude.reset()
        altitude.targetAltitude = max(state.altitude, 1.0)
        onArmedChange?(true)
    }

    /// 上锁，电机停转。
    public func disarm() {
        guard state.mode != .disarmed else { return }
        state.mode = .disarmed
        state.motorSpeeds = [0, 0, 0, 0]
        onArmedChange?(false)
    }

    /// 复位到出生点。
    public func respawn() {
        let heading = state.initialHeading
        state = FlightState(position: Vec3(0, 0, 0))
        state.initialHeading = heading
        altitude.reset()
        input = .neutral
    }

    /// 推进一帧。`timestamp` 为秒。
    public func update(timestamp: Float) {
        let dt: Float
        if lastTimestamp == 0 {
            dt = FlightDynamics.fixedTimeStep
        } else {
            dt = min(timestamp - lastTimestamp, 0.25)
        }
        lastTimestamp = timestamp
        lastUpdateTimestamp = timestamp

        // 固定步长累加
        accumulator += dt
        let h = FlightDynamics.fixedTimeStep
        var steps = 0
        let maxSteps = 12  // 最多补 12 步（50ms），超出部分丢弃

        let start = DispatchTime.now().uptimeNanoseconds
        while accumulator >= h && steps < maxSteps {
            physicsStep(dt: h)
            accumulator -= h
            steps += 1
        }
        if accumulator > h * Float(maxSteps) {
            accumulator = 0  // 丢弃积压，避免死亡螺旋
        }
        lastStepCount = steps
        lastPhysicsDuration = Float(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }

    /// 单个物理步。
    private func physicsStep(dt: Float) {
        var effectiveInput = input

        if state.mode == .disarmed {
            // 未解锁：电机停转，但仍模拟自由落体。
            state.motorSpeeds = [0, 0, 0, 0]
            let gravity = Vec3(0, -environment.gravity, 0)
            state.velocity += gravity * dt
            state.position += state.velocity * dt
            state.energyUsed += 0.5 * dt
            dynamics.handleGroundCollision(state: &state, environment: environment)
            return
        }

        if state.mode == .crashed {
            state.velocity += Vec3(0, -environment.gravity, 0) * dt
            state.position += state.velocity * dt
            dynamics.handleGroundCollision(state: &state, environment: environment)
            return
        }

        // --- 自稳：把摇杆输入转成目标角速度，再由 PD 控制器驱动电机 ---
        if stabilizedEnabled {
            let targetRate = stabilized.targetAngularVelocity(input: input, state: state)
            // 姿态 PD：角速度误差 → 附加的电机差动指令
            let rateError = targetRate - state.angularVelocity
            let gyroGain: Float = 0.055
            let attitudeCmd = Vec3(
                rateError.x * gyroGain,
                0,  // 偏航单独处理
                rateError.z * gyroGain
            )
            // 把姿态修正折算成 roll/pitch 指令（幅度与姿态修正力矩成正比）
            effectiveInput.roll = clamp(effectiveInput.roll + attitudeCmd.x, -1, 1)
            effectiveInput.pitch = clamp(effectiveInput.pitch + attitudeCmd.z, -1, 1)

            // 偏航：直接用摇杆 + 转速差动已由 mix 处理
            effectiveInput.yaw = clamp(effectiveInput.yaw, -1, 1)
        }

        // --- 定高：高度模式由控制器输出油门 ---
        switch input.altitudeMode {
        case .manual:
            break
        case .hold:
            effectiveInput.throttle = altitude.update(state: state, dt: dt)
        }

        let wasCrashed = state.mode == .crashed
        dynamics.step(state: &state, input: effectiveInput, environment: environment, dt: dt)

        if !wasCrashed && state.mode == .crashed {
            onCrash?(state.lastImpactSpeed)
        }

        // 触地检测：落地且速度很低 → 自动上锁
        if state.onGround && state.velocity.y <= 0.01 && state.airspeed < 0.6 && state.mode != .crashed {
            // 不自动上锁，交给玩家（真机也一样），但记录状态供 UI 显示
        }
    }
}
