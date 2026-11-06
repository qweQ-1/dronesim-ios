import XCTest
@testable import DroneSim

/// 飞行管理器、自稳控制器、高度控制器的单元测试。
final class FlightManagerTests: XCTestCase {

    func testArmTransitionsToStabilized() {
        let manager = FlightManager()
        XCTAssertFalse(manager.isArmed)
        manager.arm()
        XCTAssertTrue(manager.isArmed)
        XCTAssertEqual(manager.state.mode, .stabilized)
    }

    func testDisarmStopsMotors() {
        let manager = FlightManager()
        manager.arm()
        manager.disarm()
        XCTAssertFalse(manager.isArmed)
        XCTAssertEqual(manager.state.motorSpeeds, [0, 0, 0, 0])
    }

    func testCrashCallbackFires() {
        let manager = FlightManager()
        var crashed = false
        manager.onCrash = { _ in crashed = true }
        manager.arm()
        // 强制翻转
        manager.state.attitude = Quat(axis: Vec3(1, 0, 0), angle: .pi)
        manager.state.position = Vec3(0, 30, 0)
        manager.input = ControlInput(throttle: 0.9)
        var t: Float = 0
        for _ in 0..<60 {
            t += 1.0 / 60.0
            manager.update(timestamp: t)
        }
        XCTAssertTrue(crashed || manager.state.mode == .crashed)
    }

    func testRespawnResetsState() {
        let manager = FlightManager()
        manager.arm()
        manager.state.position = Vec3(100, 50, 100)
        manager.respawn()
        XCTAssertEqual(manager.state.position, Vec3(0, 0, 0))
        XCTAssertEqual(manager.state.mode, .disarmed)
    }

    func testUpdateAdvancesSimulation() {
        let manager = FlightManager()
        manager.arm()
        manager.state.position = Vec3(0, 50, 0)
        manager.input = ControlInput(throttle: 0.9)
        // 推进 1 秒
        var t: Float = 0
        for _ in 0..<60 {
            t += 1.0 / 60.0
            manager.update(timestamp: t)
        }
        XCTAssertGreaterThan(manager.state.velocity.y, 0.3)
    }

    func testFixedStepAccumulatorKeepsPhysicsStable() {
        let manager = FlightManager()
        manager.arm()
        manager.state.position = Vec3(0, 50, 0)
        manager.input = ControlInput(throttle: 0.8)
        // 用很低的帧率推进，物理步数应当被限制住（不会死亡螺旋）
        var t: Float = 0
        for _ in 0..<10 {
            t += 0.2   // 每帧 200ms
            manager.update(timestamp: t)
        }
        XCTAssertLessThanOrEqual(manager.lastStepCount, 12)
        XCTAssertFalse(manager.state.position.y.isNaN)
    }

    // MARK: 自稳控制器

    func testStabilizedControllerReturnsTowardLevel() {
        let controller = StabilizedController(mode: .stabilized)
        // 绕机体右轴转 0.5 rad = 抬头 0.5 rad
        var tilted = FlightState()
        tilted.attitude = Quat(axis: Vec3(1, 0, 0), angle: 0.5)
        let rate = controller.targetAngularVelocity(input: .neutral, state: tilted)
        // 机体 +x 绕右轴、正为抬头；当前是抬头姿态，应给出低头修正（负值）
        XCTAssertLessThan(rate.x, -0.05, "抬头姿态应产生低头修正")
        // 侧倾方向没有偏差，横滚分量接近 0
        XCTAssertEqual(rate.z, 0, accuracy: 0.05)
    }

    func testStabilizedControllerLevelsRoll() {
        let controller = StabilizedController(mode: .stabilized)
        // 绕机体后轴转 -0.5 rad = 右滚 0.5 rad
        var tilted = FlightState()
        tilted.attitude = Quat(axis: Vec3(0, 0, 1), angle: -0.5)
        let rate = controller.targetAngularVelocity(input: .neutral, state: tilted)
        // 机体 +z 绕后轴、正为左滚；右滚姿态需要左滚修正（正值）
        XCTAssertGreaterThan(rate.z, 0.05, "右滚姿态应产生左滚修正")
    }

    func testStabilizedModeLimitsTiltInsteadOfSpinning() {
        // 自稳是 Angle 模式：推住杆只到限幅倾角，不会一直滚
        let controller = StabilizedController(mode: .stabilized, maxTiltAngle: 0.5)
        // 已经到达目标倾角时，角速度指令应当接近 0（不再继续加速）
        var state = FlightState()
        state.attitude = Quat(axis: Vec3(0, 0, 1), angle: -0.5)   // 右滚到限幅
        let rate = controller.targetAngularVelocity(input: ControlInput(roll: 1.0), state: state)
        XCTAssertEqual(rate.z, 0, accuracy: 0.1, "到达限幅倾角后不应继续给出滚转指令")
    }

    func testAcroModeHasNoAttitudeCorrection() {
        let controller = StabilizedController(mode: .acro)
        var tilted = FlightState()
        tilted.attitude = Quat(axis: Vec3(1, 0, 0), angle: 0.5)
        let rate = controller.targetAngularVelocity(input: .neutral, state: tilted)
        XCTAssertEqual(rate.x, 0, accuracy: 1e-6)
        XCTAssertEqual(rate.z, 0, accuracy: 1e-6)
    }

    func testStabilizedModeRespondsToStick() {
        let controller = StabilizedController(mode: .stabilized)
        let rate = controller.targetAngularVelocity(input: ControlInput(roll: 1.0), state: FlightState())
        // 推右滚杆 → 目标是右滚姿态 → 机体 +z 为左滚，所以是负值
        XCTAssertLessThan(rate.z, -0.5, "推满右滚杆应给出明显的右滚角速度")
    }

    func testAngularRateIsClamped() {
        let controller = StabilizedController(mode: .acro, maxAngularRate: 5)
        let rate = controller.targetAngularVelocity(input: ControlInput(roll: 1.0, pitch: 1.0), state: FlightState())
        XCTAssertLessThanOrEqual(abs(rate.x), 5.001)
        XCTAssertLessThanOrEqual(abs(rate.z), 5.001)
    }

    func testStickDirectionsMapToCorrectBodyAxes() {
        // 这是修过的一个真实 bug：控制器曾经把横滚放进 .x、俯仰放进 .z，
        // 与机体的实际轴向相反（.x 是俯仰、.z 是横滚）。
        let controller = StabilizedController(mode: .acro, maxAngularRate: 4)

        // 只有俯仰杆：角速度应出现在 .x
        let pitchOnly = controller.targetAngularVelocity(
            input: ControlInput(pitch: 1.0), state: FlightState())
        XCTAssertLessThan(pitchOnly.x, -0.5, "低头杆应产生绕右轴的负向角速度")
        XCTAssertEqual(pitchOnly.z, 0, accuracy: 1e-5, "俯仰杆不应产生横滚角速度")

        // 只有横滚杆：角速度应出现在 .z
        let rollOnly = controller.targetAngularVelocity(
            input: ControlInput(roll: 1.0), state: FlightState())
        XCTAssertLessThan(rollOnly.z, -0.5, "右滚杆应产生绕后轴的负向角速度")
        XCTAssertEqual(rollOnly.x, 0, accuracy: 1e-5, "横滚杆不应产生俯仰角速度")

        // 只有偏航杆：角速度应出现在 .y
        let yawOnly = controller.targetAngularVelocity(
            input: ControlInput(yaw: 1.0), state: FlightState())
        XCTAssertLessThan(yawOnly.y, -0.5, "右偏杆应产生绕上轴的负向角速度")
        XCTAssertEqual(yawOnly.x, 0, accuracy: 1e-5)
    }

    // MARK: 高度控制器

    func testAltitudeControllerReducesError() {
        var controller = AltitudeController(targetAltitude: 10)
        let state = FlightState(position: Vec3(0, 2, 0))
        var output = controller.update(state: state, dt: 0.1)
        XCTAssertGreaterThan(output, 0.5, "低于目标高度应该输出较大油门")
        output = controller.update(state: FlightState(position: Vec3(0, 20, 0)), dt: 0.1)
        XCTAssertLessThan(output, 0.5, "高于目标高度应该输出较小油门")
    }

    func testAltitudeControllerOutputIsBounded() {
        var controller = AltitudeController(targetAltitude: 100)
        let output = controller.update(state: FlightState(position: Vec3(0, 0, 0)), dt: 0.1)
        XCTAssertGreaterThanOrEqual(output, controller.outputMin)
        XCTAssertLessThanOrEqual(output, controller.outputMax)
    }

    func testAltitudeControllerIntegralResets() {
        var controller = AltitudeController(targetAltitude: 10)
        _ = controller.update(state: FlightState(position: Vec3(0, 0, 0)), dt: 0.1)
        XCTAssertNotEqual(controller.integral, 0)
        controller.reset()
        XCTAssertEqual(controller.integral, 0)
    }
}
