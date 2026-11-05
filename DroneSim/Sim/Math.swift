import Foundation
import simd

// MARK: - 数学工具

/// 三维向量（SIMD 对齐，便于直接喂给 Metal）。
public struct Vec3: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float

    @inlinable
    public init(_ x: Float = 0, _ y: Float = 0, _ z: Float = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)
    public static let up = Vec3(0, 1, 0)

    @inlinable public var length: Float { (x * x + y * y + z * z).squareRoot() }

    @inlinable public var lengthSquared: Float { x * x + y * y + z * z }

    /// 逐分量与另一个向量相差是否在容差内（给测试用，避免依赖 FloatingPoint 协议）。
    @inlinable public func isClose(to other: Vec3, accuracy: Float) -> Bool {
        abs(x - other.x) <= accuracy
            && abs(y - other.y) <= accuracy
            && abs(z - other.z) <= accuracy
    }

    @inlinable public var normalized: Vec3 {
        let l = length
        guard l > 1e-8 else { return .zero }
        return Vec3(x / l, y / l, z / l)
    }

    @inlinable public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }

    @inlinable public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }

    @inlinable public static func * (a: Vec3, s: Float) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }

    @inlinable public static func * (s: Float, a: Vec3) -> Vec3 { a * s }

    @inlinable public static func / (a: Vec3, s: Float) -> Vec3 { Vec3(a.x / s, a.y / s, a.z / s) }

    @inlinable public static prefix func - (a: Vec3) -> Vec3 { Vec3(-a.x, -a.y, -a.z) }

    @inlinable public static func += (a: inout Vec3, b: Vec3) { a = a + b }

    @inlinable public static func -= (a: inout Vec3, b: Vec3) { a = a - b }

    @inlinable public static func *= (a: inout Vec3, s: Float) { a = a * s }

    /// 标量乘积。
    @inlinable public static func * (a: Vec3, b: Vec3) -> Float { a.x * b.x + a.y * b.y + a.z * b.z }

    @inlinable public func cross(_ b: Vec3) -> Vec3 {
        Vec3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x)
    }

    @inlinable public func distance(to b: Vec3) -> Float { (self - b).length }

    /// 线性插值。
    @inlinable public static func lerp(_ a: Vec3, _ b: Vec3, _ t: Float) -> Vec3 {
        Vec3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
    }
}

/// 标量插值。
@inlinable public func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

/// 把角度归一化到 (-π, π]。
@inlinable public func normalizeAngle(_ a: Float) -> Float {
    var x = a
    while x > .pi { x -= 2 * .pi }
    while x <= -.pi { x += 2 * .pi }
    return x
}

/// 指数平滑，帧率无关。`rate` 越大越快跟随。
@inlinable public func expSmooth(_ current: Float, _ target: Float, rate: Float, dt: Float) -> Float {
    let alpha = 1 - exp(-rate * dt)
    return current + (target - current) * alpha
}

/// 指数平滑（向量版）。
@inlinable public func expSmooth(_ current: Vec3, _ target: Vec3, rate: Float, dt: Float) -> Vec3 {
    let alpha = 1 - exp(-rate * dt)
    return current + (target - current) * alpha
}

/// 角度指数平滑，走最短弧。
@inlinable public func expSmoothAngle(_ current: Float, _ target: Float, rate: Float, dt: Float) -> Float {
    let delta = normalizeAngle(target - current)
    let alpha = 1 - exp(-rate * dt)
    return current + delta * alpha
}

/// 限幅。
@inlinable public func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
    min(max(v, lo), hi)
}

/// 死区（摇杆居中附近的小幅输入归零，避免手抖）。
@inlinable public func applyDeadzone(_ v: Float, _ dz: Float) -> Float {
    let mag = abs(v)
    guard mag > dz else { return 0 }
    return sign(v) * (mag - dz) / (1 - dz)
}

/// 向量线性插值（SIMD3）。
@inlinable public func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}

/// 平滑阶跃函数。
@inlinable public func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
}
