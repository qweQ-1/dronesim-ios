import XCTest
@testable import DroneSim

/// 端到端飞行测试：把「解锁 → 起飞 → 悬停 → 移动」整条链路跑一遍。
///
/// 这些是照着真机上出现的问题写的：
/// - 无人机完全不动（摇杆和物理没接上）
/// - 定高一开就往上飞（定高油门映射错误）
/// - 推杆方向不对（混控横滚/俯仰写反）
final class FlightEndToEndTests: XCTestCase {

    /// 按固定帧率推进仿真（模拟 CADisplayLink 的 60Hz 驱动）。
    private func fly(_ manager: FlightManager, seconds: Float, fps: Float = 60) {
        let frames = Int(seconds * fps)
        var t: Float = 0
        for _ in 0..<frames {
            t += 1 / fps
            manager.update(timestamp: t)
        }
    }

    /// 解锁后用悬停油门应该能稳定悬停，不升不降。
    func testArmAndHoverHoldsAltitude() {
        let manager = FlightManager()
        manager.state.position = Vec3(0, 20, 0)
        manager.arm()
        manager.input = ControlInput(throttle: DroneSpec.hoverThrottle)

        fly(manager, seconds: 3)

        let drift = abs(manager.state.altitude - 20)
        XCTAssertLessThan(drift, 3.0, "悬停时高度漂移应很小，实际 \(drift)")
        XCTAssertFalse(manager.state.mode == .crashed)
    }

    /// 推满横滚杆，机体应该向右滚（横滚杆要驱动横滚轴）。
    func testRollStickRollsTheDrone() {
        let manager = FlightManager()
        manager.state.position = Vec3(0, 40, 0)
        manager.arm()
        manager.input = ControlInput(throttle: DroneSpec.hoverThrottle)
        fly(manager, seconds: 0.5)

        manager.input.roll = 1.0
        fly(manager, seconds: 0.35)

        let frame = BodyFrame(quaternion: manager.state.attitude)
        // 右滚 → 右侧下沉 → right.y 为负
        XCTAssertLessThan(frame.right.y, -0.05, "推满右滚杆后机体应向右倾斜")
    }

    /// 推满俯仰杆，机体应该低头并向前飞（位置往机头方向移动）。
    func testPitchStickMovesForward() {
        let manager = FlightManager()
        manager.state.position = Vec3(0, 40, 0)
        manager.arm()
        manager.input = ControlInput(throttle: DroneSpec.hoverThrottle)
        fly(manager, seconds: 0.5)

        let startZ = manager.state.position.z
        manager.input.pitch = 1.0
        fly(manager, seconds: 1.0)

        let frame = BodyFrame(quaternion: manager.state.attitude)
        // 低头 → 前轴低于水平
        XCTAssertLessThan(frame.forward.y, -0.02, "推满俯仰杆后机头应向下")

        // 机头朝 -z（初始朝向），所以前进时 z 应该变小
        let moved = manager.state.position.z - startZ
        XCTAssertLessThan(moved, -0.5, "向前推杆应该让机体向前移动，实际位移 \(moved)")
    }

    /// 定高模式应该把机体稳在目标高度，而不是一路往上冲。
    func testAltitudeHoldConvergesInsteadOfClimbing() {
        let manager = FlightManager()
        manager.state.position = Vec3(0, 15, 0)
        manager.arm()

        // 目标高度 15m（和当前一致）——定高不应该让它飞走
        manager.altitude.targetAltitude = 15
        manager.input.altitudeMode = .hold(altitude: 15)
        fly(manager, seconds: 5)

        let drift = abs(manager.state.altitude - 15)
        XCTAssertLessThan(drift, 4.0, "定高应稳定在目标高度附近，实际漂移 \(drift)")
        XCTAssertLessThan(manager.state.velocity.y, 1.0, "定高不应持续上升")
    }

    /// 定高模式下从低处起飞，应该爬到目标高度并停住。
    func testAltitudeHoldClimbsToTarget() {
        let manager = FlightManager()
        manager.state.position = Vec3(0, 2, 0)
        manager.arm()
        manager.altitude.targetAltitude = 25
        manager.input.altitudeMode = .hold(altitude: 25)

        fly(manager, seconds: 8)

        XCTAssertGreaterThan(manager.state.altitude, 18, "定高应该爬到接近目标高度")
        XCTAssertLessThan(manager.state.altitude, 32, "定高不应该冲过目标高度太多")
    }

    /// 摇杆回中后机体应该回到水平（Angle 模式的自稳）。
    func testStabilizedReturnsToLevelAfterStickRelease() {
        let manager = FlightManager()
        manager.state.position = Vec3(0, 40, 0)
        manager.arm()
        manager.input = ControlInput(throttle: DroneSpec.hoverThrottle)
        fly(manager, seconds: 0.5)

        // 推杆滚转，然后回中
        manager.input.roll = 1.0
        fly(manager, seconds: 1.0)
        manager.input.roll = 0
        fly(manager, seconds: 2.0)

        let frame = BodyFrame(quaternion: manager.state.attitude)
        XCTAssertGreaterThan(frame.up.y, 0.95, "松杆后机体应自动回到水平")
    }
}
