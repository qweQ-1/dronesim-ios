import XCTest
@testable import DroneSim

/// 诊断测试：把悬停时的关键数值放进断言失败消息里。
///
/// XCTest 的 print 会被 CI 的日志过滤器吃掉，所以只能让断言故意失败，
/// 数值出现在 ##[error] 行里才看得见。定位到问题后删掉这个文件。
final class DiagnosticTests: XCTestCase {

    func testHoverDiagnostics() {
        var dynamics = FlightDynamics()
        let spec = dynamics.spec

        var probe = FlightState(position: Vec3(0, 100, 0))
        probe.mode = .stabilized
        var input = ControlInput(throttle: 0.42)
        input.altitudeMode = .manual

        let commanded = dynamics.commandedRotorSpeeds(input: input, state: probe)
        let thrustPer = dynamics.thrust(forRotorSpeed: commanded[0])
        let totalThrust = thrustPer * 4
        let weight = spec.mass * 9.81

        var state = FlightState(position: Vec3(0, 100, 0))
        state.mode = .stabilized
        for _ in 0..<240 {
            dynamics.step(state: &state, input: input, environment: .calm,
                          dt: FlightDynamics.fixedTimeStep)
        }

        let report = """
        DIAG | 怠速=\(spec.idleRotorSpeed) 悬停=\(spec.hoverRotorSpeed) 满速=\(spec.maxRotorSpeed)
        DIAG | 指令转速=\(commanded)
        DIAG | 单旋翼推力=\(thrustPer) 总推力=\(totalThrust) 重力=\(weight)
        DIAG | 推力系数=\(spec.thrustCoefficient) 电机上限=\(dynamics.motor.maxThrust)
        DIAG | 1秒后 vy=\(state.velocity.y) y=\(state.position.y) 电机=\(state.motorSpeeds)
        DIAG | 姿态 up.y=\(state.attitude.up.y) mode=\(state.mode)
        """
        XCTFail(report)
    }
}
