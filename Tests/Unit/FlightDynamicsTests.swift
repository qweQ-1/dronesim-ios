import XCTest
@testable import DroneSim

/// 飞行动力学的单元测试：验证悬停、稳定性、碰撞、能量等核心行为。
final class FlightDynamicsTests: XCTestCase {

    /// 用固定步长推进指定秒数。
    private func simulate(_ dynamics: inout FlightDynamics,
                          state: inout FlightState,
                          input: ControlInput,
                          seconds: Float,
                          environment: Environment = .calm) {
        let steps = Int(seconds / FlightDynamics.fixedTimeStep)
        for _ in 0..<steps {
            dynamics.step(state: &state, input: input, environment: environment,
                          dt: FlightDynamics.fixedTimeStep)
        }
    }

    func testFixedTimeStepIsSmallEnoughForStability() {
        // 240Hz 是 4K 视频标准；如果改动这个值，要同步改这里
        XCTAssertEqual(FlightDynamics.fixedTimeStep, 1.0 / 240.0, accuracy: 1e-6)
    }

    func testDisarmedDroneFallsToGround() {
        var dynamics = FlightDynamics()
        var state = FlightState(position: Vec3(0, 50, 0))
        state.mode = .disarmed
        simulate(&dynamics, state: &state, input: .neutral, seconds: 2.0)
        XCTAssertLessThan(state.position.y, 50)
        XCTAssertLessThan(state.position.y, 45)
    }

    func testHoverThrustBalancesGravity() {
        // 油门映射的定义是：0 → 怠速，0.42 → 悬停转速，1 → 满速。
        // 所以悬停油门就是 0.42（之前这里用错公式反推，
        // 把它当成「hover→max 段的比例」，算出的油门远大于悬停点，
        // 于是机体一路加速上升 17 米）。
        var dynamics = FlightDynamics()
        let spec = dynamics.spec

        // 先确认 0.42 油门确实映射到悬停转速
        let hoverSpeed = spec.hoverRotorSpeed
        var probe = FlightState()
        probe.mode = .stabilized
        var probeInput = ControlInput(throttle: 0.42)
        probeInput.altitudeMode = .manual
        let commanded = dynamics.commandedRotorSpeeds(input: probeInput, state: probe)
        XCTAssertEqual(commanded[0], hoverSpeed, accuracy: hoverSpeed * 0.02,
                       "油门 0.42 应对应悬停转速")

        var state = FlightState(position: Vec3(0, 10, 0))
        state.mode = .stabilized
        var input = ControlInput(throttle: 0.42)
        input.altitudeMode = .manual

        let before = state.position.y
        simulate(&dynamics, state: &state, input: input, seconds: 3.0)
        let drift = state.position.y - before
        XCTAssertLessThan(abs(drift), 1.5, "悬停时高度漂移应很小，实际 \(drift)")
    }

    func testFullThrottleAcceleratesUpward() {
        var dynamics = FlightDynamics()
        var state = FlightState(position: Vec3(0, 10, 0))
        state.mode = .stabilized
        var input = ControlInput(throttle: 1.0)
        input.altitudeMode = .manual
        simulate(&dynamics, state: &state, input: input, seconds: 1.0)
        XCTAssertGreaterThan(state.velocity.y, 0.5, "满油门应该明显上升")
    }

    func testZeroThrottleDoesNotClimb() {
        var dynamics = FlightDynamics()
        var state = FlightState(position: Vec3(0, 10, 0))
        state.mode = .stabilized
        var input = ControlInput(throttle: 0.0)
        input.altitudeMode = .manual
        simulate(&dynamics, state: &state, input: input, seconds: 0.5)
        XCTAssertLessThan(state.velocity.y, 0.5)
    }

    func testGroundCollisionStopsFall() {
        var dynamics = FlightDynamics()
        var state = FlightState(position: Vec3(0, 3, 0), mode: .disarmed)
        simulate(&dynamics, state: &state, input: .neutral, seconds: 3.0)
        XCTAssertGreaterThanOrEqual(state.position.y, 0)
        XCTAssertLessThan(state.position.y, 0.5, "应该停在地面上")
        XCTAssertTrue(state.onGround)
    }

    func testInvertedAttitudeCrashes() {
        var dynamics = FlightDynamics()
        // 倒飞姿态：up 指向下
        var state = FlightState(position: Vec3(0, 20, 0))
        state.attitude = Quat(axis: Vec3(1, 0, 0), angle: .pi)
        state.mode = .stabilized
        var input = ControlInput(throttle: 0.6)
        input.altitudeMode = .manual
        simulate(&dynamics, state: &state, input: input, seconds: 0.2)
        XCTAssertEqual(state.mode, .crashed)
    }

    func testEnergyIsConsumedOverTime() {
        var dynamics = FlightDynamics()
        var state = FlightState(position: Vec3(0, 10, 0))
        state.mode = .stabilized
        var input = ControlInput(throttle: 0.8)
        input.altitudeMode = .manual
        simulate(&dynamics, state: &state, input: input, seconds: 2.0)
        XCTAssertGreaterThan(state.energyUsed, 0)
        XCTAssertLessThan(state.batteryFraction(spec: dynamics.spec), 1.0)
    }

    func testMotorSpeedsConvergeToCommand() {
        var dynamics = FlightDynamics()
        var state = FlightState(position: Vec3(0, 10, 0))
        state.mode = .stabilized
        var input = ControlInput(throttle: 0.7)
        input.altitudeMode = .manual
        simulate(&dynamics, state: &state, input: input, seconds: 2.0)

        let commands = dynamics.commandedRotorSpeeds(input: input, state: state)
        for i in 0..<4 {
            XCTAssertEqual(state.motorSpeeds[i], commands[i], accuracy: 1.0,
                           "电机 \(i) 转速应收敛到指令值")
        }
    }

    func testRollCommandDifferentializesMotors() {
        let dynamics = FlightDynamics()
        let state = FlightState()
        var input = ControlInput(throttle: 0.5, roll: 1.0)
        input.altitudeMode = .manual
        let speeds = dynamics.commandedRotorSpeeds(input: input, state: state)
        // 右倾 → 右侧电机（0=FR, 3=RR）加速，左侧（1=FL, 2=RL）减速
        XCTAssertGreaterThan(speeds[0], speeds[1])
        XCTAssertGreaterThan(speeds[3], speeds[2])
    }

    func testPitchCommandDifferentializesMotors() {
        let dynamics = FlightDynamics()
        let state = FlightState()
        var input = ControlInput(throttle: 0.5, pitch: 1.0)
        input.altitudeMode = .manual
        let speeds = dynamics.commandedRotorSpeeds(input: input, state: state)
        // 低头前进 → 前电机（0, 1）加速，后电机（2, 3）减速
        XCTAssertGreaterThan(speeds[0], speeds[2])
        XCTAssertGreaterThan(speeds[1], speeds[3])
    }

    func testYawCommandDifferentializesMotorsDiagonally() {
        let dynamics = FlightDynamics()
        let state = FlightState()
        var input = ControlInput(throttle: 0.5, yaw: 1.0)
        input.altitudeMode = .manual
        let speeds = dynamics.commandedRotorSpeeds(input: input, state: state)
        // 右转 → 逆时针电机（1=FL, 2=RL）加速，顺时针（0=FR, 3=RR）减速
        XCTAssertGreaterThan(speeds[1], speeds[0])
        XCTAssertGreaterThan(speeds[2], speeds[3])
    }

    func testMotorSpeedsStayWithinLimits() {
        let dynamics = FlightDynamics()
        let state = FlightState()
        var input = ControlInput(throttle: 1.0, roll: 1.0, pitch: 1.0, yaw: 1.0)
        input.altitudeMode = .manual
        let speeds = dynamics.commandedRotorSpeeds(input: input, state: state)
        for s in speeds {
            XCTAssertLessThanOrEqual(s, dynamics.spec.maxRotorSpeed + 0.001)
            XCTAssertGreaterThan(s, 0)
        }
    }

    func testSimulationDoesNotProduceNaN() {
        var dynamics = FlightDynamics()
        var state = FlightState(position: Vec3(0, 20, 0))
        state.mode = .stabilized
        var input = ControlInput(throttle: 0.9, roll: 0.5, pitch: 0.3, yaw: 0.8)
        input.altitudeMode = .manual
        simulate(&dynamics, state: &state, input: input, seconds: 5.0)

        XCTAssertFalse(state.position.x.isNaN)
        XCTAssertFalse(state.position.y.isNaN)
        XCTAssertFalse(state.position.z.isNaN)
        XCTAssertFalse(state.velocity.x.isNaN)
        XCTAssertFalse(state.attitude.w.isNaN)
        XCTAssertEqual(state.attitude.length, 1, accuracy: 1e-3)
    }

    func testWindAffectsDrift() {
        var dynamics = FlightDynamics()
        var state = FlightState(position: Vec3(0, 30, 0))
        state.mode = .stabilized
        var input = ControlInput(throttle: 0.45)
        input.altitudeMode = .manual
        let environment = Environment(wind: Vec3(6, 0, 0), turbulence: 0)
        simulate(&dynamics, state: &state, input: input, seconds: 2.0,
                 environment: environment)
        XCTAssertGreaterThan(state.velocity.x, 0.5, "顺风应该产生正向漂移")
    }

    func testThrustHeadroomDecreasesWithThrottle() {
        var dynamics = FlightDynamics()
        var state = FlightState(position: Vec3(0, 30, 0))
        state.mode = .stabilized
        var input = ControlInput(throttle: 1.0)
        input.altitudeMode = .manual
        simulate(&dynamics, state: &state, input: input, seconds: 2.0)
        XCTAssertLessThan(state.thrustHeadroom, 0.2, "满油门时推力余量应接近 0")
    }
}
