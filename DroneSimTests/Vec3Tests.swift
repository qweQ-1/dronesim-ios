import XCTest
@testable import DroneSim

/// Vec3 与数学工具的单元测试。
final class Vec3Tests: XCTestCase {

    func testLengthAndNormalized() {
        let v = Vec3(3, 4, 0)
        XCTAssertEqual(v.length, 5, accuracy: 1e-5)
        XCTAssertEqual(v.normalized.length, 1, accuracy: 1e-5)
    }

    func testNormalizeZeroVectorIsSafe() {
        let v = Vec3(0, 0, 0).normalized
        XCTAssertEqual(v, Vec3(0, 0, 0))
    }

    func testDotProduct() {
        let a = Vec3(1, 2, 3)
        let b = Vec3(4, 5, 6)
        XCTAssertEqual(a * b, 32, accuracy: 1e-5)
    }

    func testCrossProductIsPerpendicular() {
        let a = Vec3(1, 0, 0)
        let b = Vec3(0, 1, 0)
        let c = a.cross(b)
        XCTAssertEqual(c, Vec3(0, 0, 1), accuracy: 1e-6)
        XCTAssertEqual(a * c, 0, accuracy: 1e-6)
        XCTAssertEqual(b * c, 0, accuracy: 1e-6)
    }

    func testVectorArithmetic() {
        let a = Vec3(1, 2, 3)
        let b = Vec3(4, 5, 6)
        XCTAssertEqual(a + b, Vec3(5, 7, 9))
        XCTAssertEqual(b - a, Vec3(3, 3, 3))
        XCTAssertEqual(a * 2, Vec3(2, 4, 6))
        XCTAssertEqual(-a, Vec3(-1, -2, -3))
    }

    func testNormalizeAngleWrapsToPiRange() {
        XCTAssertEqual(normalizeAngle(0), 0, accuracy: 1e-6)
        XCTAssertEqual(normalizeAngle(.pi * 3), .pi, accuracy: 1e-5)
        XCTAssertEqual(normalizeAngle(-.pi * 3), .pi, accuracy: 1e-5)
        XCTAssertEqual(normalizeAngle(.pi + 0.5), -.pi + 0.5, accuracy: 1e-5)
    }

    func testClampBounds() {
        XCTAssertEqual(clamp(5, 0, 1), 1)
        XCTAssertEqual(clamp(-5, 0, 1), 0)
        XCTAssertEqual(clamp(0.5, 0, 1), 0.5)
    }

    func testApplyDeadzone() {
        XCTAssertEqual(applyDeadzone(0.05, 0.1), 0)
        XCTAssertEqual(applyDeadzone(-0.05, 0.1), 0)
        XCTAssertEqual(applyDeadzone(1.0, 0.1), 1.0, accuracy: 1e-5)
        XCTAssertEqual(applyDeadzone(-1.0, 0.1), -1.0, accuracy: 1e-5)
        // 死区之外应当线性映射到 0...1
        XCTAssertEqual(applyDeadzone(0.55, 0.1), 0.5, accuracy: 1e-5)
    }

    func testExpSmoothConvergesToTarget() {
        var value: Float = 0
        for _ in 0..<200 {
            value = expSmooth(value, 10, rate: 10, dt: 1.0 / 60.0)
        }
        XCTAssertEqual(value, 10, accuracy: 0.05)
    }

    func testExpSmoothIsFrameRateIndependent() {
        var fast: Float = 0
        for _ in 0..<120 { fast = expSmooth(fast, 1, rate: 5, dt: 1.0 / 120.0) }
        var slow: Float = 0
        for _ in 0..<60 { slow = expSmooth(slow, 1, rate: 5, dt: 1.0 / 60.0) }
        XCTAssertEqual(fast, slow, accuracy: 0.01)
    }

    func testLerp() {
        XCTAssertEqual(lerp(Vec3(0, 0, 0), Vec3(10, 20, 30), 0.5), Vec3(5, 10, 15))
        XCTAssertEqual(lerp(0.0, 10.0, 0.25), 2.5)
    }

    func testSmoothstep() {
        XCTAssertEqual(smoothstep(0, 1, 0.5), 0.5, accuracy: 1e-5)
        XCTAssertEqual(smoothstep(0, 1, -1), 0)
        XCTAssertEqual(smoothstep(0, 1, 2), 1)
    }
}
