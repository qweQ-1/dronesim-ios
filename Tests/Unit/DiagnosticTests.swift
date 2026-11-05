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

        // 必须写成单行：CI 的日志会把多行消息截断，只看得到第一行
        let report = "DIAG idle=\(spec.idleRotorSpeed) hover=\(spec.hoverRotorSpeed)"
            + " cmd=\(commanded[0]) per=\(thrustPer) total=\(totalThrust) weight=\(weight)"
            + " k=\(spec.thrustCoefficient) cap=\(dynamics.motor.maxThrust)"
            + " | 1s: vy=\(state.velocity.y) y=\(state.position.y) m=\(state.motorSpeeds[0])"
            + " up=\(state.attitude.up.y) mode=\(state.mode)"
        XCTFail(report)
    }
}
