import XCTest
@testable import DroneSim

/// 诊断测试：把悬停时的关键数值打印出来，便于定位物理标定问题。
/// 这些断言故意宽松，作用是把数值暴露在 CI 日志里。
final class DiagnosticTests: XCTestCase {

    func testHoverDiagnostics() {
        var dynamics = FlightDynamics()
        let spec = dynamics.spec

        let hover = spec.hoverRotorSpeed
        let idle = spec.idleRotorSpeed
        var state = FlightState(position: Vec3(0, 100, 0))
        state.mode = .stabilized
        var input = ControlInput(throttle: 0.42)
        input.altitudeMode = .manual

        let commanded = dynamics.commandedRotorSpeeds(input: input, state: state)
        let thrustPer = dynamics.thrust(forRotorSpeed: commanded[0])
        let total = thrustPer * 4
        let weight = spec.mass * 9.81

        print("DIAG idle=\(idle) hover=\(hover) maxRotorSpeed=\(spec.maxRotorSpeed)")
        print("DIAG commanded=\(commanded)")
        print("DIAG thrustPer=\(thrustPer) total=\(total) weight=\(weight)")
        print("DIAG thrustCoefficient=\(spec.thrustCoefficient) motorMax=\(dynamics.motor.maxThrust)")

        // 跑一会儿看实际竖直速度
        var state2 = FlightState(position: Vec3(0, 100, 0))
        state2.mode = .stabilized
        for _ in 0..<240 {
            dynamics.step(state: &state2, input: input, environment: .calm,
                          dt: FlightDynamics.fixedTimeStep)
        }
        print("DIAG after 1s: vy=\(state2.velocity.y) y=\(state2.position.y) motors=\(state2.motorSpeeds)")
        XCTAssertTrue(true)
    }
}
