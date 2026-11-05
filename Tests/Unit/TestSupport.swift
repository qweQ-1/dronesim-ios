import XCTest
import simd
@testable import DroneSim

/// 测试辅助断言。
///
/// `XCTAssertEqual(_:_:accuracy:)` 要求类型遵循 `FloatingPoint`，
/// 而 `Vec3` 是自定义的向量类型（遵循 `Equatable` 但不是标量），
/// 所以带容差的向量比较统一走这里。
func XCTAssertEqualVec(_ lhs: Vec3, _ rhs: Vec3,
                        accuracy: Float = 1e-5,
                        file: StaticString = #filePath, line: UInt = #line) {
    if !lhs.isClose(to: rhs, accuracy: accuracy) {
        XCTFail("期望 \(rhs)，实际 \(lhs)（容差 \(accuracy)）", file: file, line: line)
    }
}

/// `SIMD3<Float>` 的带容差比较。
func XCTAssertEqualVec(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>,
                        accuracy: Float = 1e-5,
                        file: StaticString = #filePath, line: UInt = #line) {
    let delta = simd_length(lhs - rhs)
    if delta > accuracy {
        XCTFail("期望 \(rhs)，实际 \(lhs)（差 \(delta)，容差 \(accuracy)）", file: file, line: line)
    }
}
