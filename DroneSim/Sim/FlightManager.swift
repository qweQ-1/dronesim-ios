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

        // --- 角速度环 ---
        //
        // 摇杆不直接驱动电机混合，而是先给出「目标角速度」，
        // 再由角速度误差换算成电机差动指令。
        //
        // 之前的写法是 `roll = 摇杆 + 误差 * 0.055`：摇杆本身就驱动混合，
        // 误差项只是个微弱修正，结果推杆后角速度会一路冲到远超目标值（疯狂翻滚），
        // 而且没有闭环，手感完全失控。
        //
        // Acro 与自稳的区别只在目标角速度怎么算（见 StabilizedController）：
        // 自稳会额外叠加把机体拉回水平的修正项。
        let targetRate = stabilized.targetAngularVelocity(input: input, state: state)
        let rateError = targetRate - state.angularVelocity
        // 误差到指令的增益：约 5.5 rad/s 的误差就打满舵
        let rateGain: Float = 0.18

        // 机体轴 → 摇杆约定：
        //   .x 绕右轴（正为抬头）→ 摇杆 pitch 正为低头
        //   .y 绕上轴（正为左偏）→ 摇杆 yaw 正为右偏
        //   .z 绕后轴（正为左滚）→ 摇杆 roll 正为右滚
        // 第一版直接把 .x 当横滚、.z 当俯仰用，轴向是错位的
        // （等于横滚杆驱动俯仰轴）。
        effectiveInput.roll = clamp(-rateError.z * rateGain, -1, 1)
        effectiveInput.pitch = clamp(-rateError.x * rateGain, -1, 1)
        effectiveInput.yaw = clamp(-rateError.y * rateGain, -1, 1)

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
