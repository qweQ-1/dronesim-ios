import XCTest
@testable import DroneSim

/// 四元数与机体坐标系的单元测试。
final class QuatTests: XCTestCase {

    func testIdentityRotatesNothing() {
        let q = Quat.identity
        let v = Vec3(1, 2, 3)
        XCTAssertEqualVec(q.rotated(v), v, accuracy: 1e-5)
    }

    func testAxisRotationByNinetyDegrees() {
        // 绕 Y 轴转 90°：x → -z
        let q = Quat(axis: Vec3(0, 1, 0), angle: .pi / 2)
        let rotated = q.rotated(Vec3(1, 0, 0))
        XCTAssertEqual(rotated.x, 0, accuracy: 1e-5)
        XCTAssertEqual(rotated.y, 0, accuracy: 1e-5)
        XCTAssertEqual(rotated.z, -1, accuracy: 1e-5)
    }

    func testQuaternionsStayNormalizedAfterIntegration() {
        var q = Quat.identity
        let omega = Vec3(0.3, 1.2, -0.7)
        for _ in 0..<1000 {
            q = q.integrated(byBodyAngularVelocity: omega, dt: 1.0 / 240.0)
        }
        XCTAssertEqual(q.length, 1, accuracy: 1e-4)
    }

    func testIntegratedRotationMatchesAxisAngle() {
        // 绕 Y 轴以 1 rad/s 转 1 秒 ≈ 1 rad
        let omega = Vec3(0, 1, 0)
        let q = Quat.identity.integrated(byBodyAngularVelocity: omega, dt: 1.0)
        let expected = Quat(axis: Vec3(0, 1, 0), angle: 1.0)
        XCTAssertEqual(q.w, expected.w, accuracy: 1e-4)
        XCTAssertEqual(q.y, expected.y, accuracy: 1e-4)
    }

    func testBodyFrameIsOrthonormal() {
        let frame = BodyFrame(forward: Vec3(0, 0, -1), up: Vec3(0, 1, 0))
        XCTAssertEqual(frame.right.length, 1, accuracy: 1e-5)
        XCTAssertEqual(frame.up.length, 1, accuracy: 1e-5)
        XCTAssertEqual(frame.forward.length, 1, accuracy: 1e-5)
        XCTAssertEqual(frame.right * frame.up, 0, accuracy: 1e-5)
        XCTAssertEqual(frame.up * frame.forward, 0, accuracy: 1e-5)
        XCTAssertEqual(frame.forward * frame.right, 0, accuracy: 1e-5)
    }

    func testBodyFrameRightHandedConvention() {
        // 右手系：right = forward × up
        let frame = BodyFrame(forward: Vec3(0, 0, -1), up: Vec3(0, 1, 0))
        // forward × up = (0,0,-1) × (0,1,0) = (1, 0, 0)
        XCTAssertEqualVec(frame.right, Vec3(1, 0, 0), accuracy: 1e-5)
    }

    func testBodyFrameRoundTrip() {
        let frame = BodyFrame(forward: Vec3(0.3, -0.2, -0.93), up: Vec3(0.1, 0.95, 0.28))
        let body = Vec3(0.3, -0.7, 0.5)
        let world = frame.toWorld(body)
        let back = frame.toBody(world)
        XCTAssertEqual(back.x, body.x, accuracy: 1e-4)
        XCTAssertEqual(back.y, body.y, accuracy: 1e-4)
        XCTAssertEqual(back.z, body.z, accuracy: 1e-4)
    }

    func testBodyFrameDegenerateUpDoesNotCrash() {
        // up 与 forward 平行
        let frame = BodyFrame(forward: Vec3(0, 1, 0), up: Vec3(0, 1, 0))
        XCTAssertEqual(frame.right.length, 1, accuracy: 1e-5)
        XCTAssertEqual(frame.up.length, 1, accuracy: 1e-5)
    }

    func testQuaternionFromForwardUpMatchesBodyFrame() {
        let forward = Vec3(0, 0, -1)
        let up = Vec3(0, 1, 0)
        let q = Quat(forward: forward, up: up)
        XCTAssertEqualVec(q.forward, forward, accuracy: 1e-4)
        XCTAssertEqualVec(q.up, up, accuracy: 1e-4)
        XCTAssertEqualVec(q.right, Vec3(1, 0, 0), accuracy: 1e-4)
    }

    func testQuaternionFromArbitraryBasis() {
        let q = Quat(forward: Vec3(0, 0, -1), up: Vec3(0.3, 0.9, 0.2))
        XCTAssertEqual(q.length, 1, accuracy: 1e-5)
        XCTAssertEqual(q.forward.y, 0, accuracy: 1e-4)
    }
}
