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
        // 机头朝下 30°
        let state = FlightState()
        var tilted = state
        tilted.attitude = Quat(axis: Vec3(1, 0, 0), angle: 0.5)
        let rate = controller.targetAngularVelocity(input: .neutral, state: tilted)
        // 俯仰角速度分量应为正（抬头回到水平）
        XCTAssertGreaterThan(rate.z, 0.05)
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
        XCTAssertGreaterThan(rate.x, 0.5, "推满横滚杆应该给出明显的横滚角速度")
    }

    func testAngularRateIsClamped() {
        let controller = StabilizedController(mode: .acro, maxAngularRate: 5)
        let rate = controller.targetAngularVelocity(input: ControlInput(roll: 1.0, pitch: 1.0), state: FlightState())
        XCTAssertLessThanOrEqual(abs(rate.x), 5.001)
        XCTAssertLessThanOrEqual(abs(rate.z), 5.001)
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
