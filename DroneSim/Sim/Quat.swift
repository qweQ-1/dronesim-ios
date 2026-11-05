import Foundation

// MARK: - 机体坐标系

/// 机体坐标系约定（右手系）：
/// - x：机头右侧
/// - y：机头上方
/// - z：机头前方（朝前为 -z，与 OpenGL/Metal 右手系一致）
///
/// 世界坐标系与机体坐标系同为右手系，y 轴向上。
public struct BodyFrame: Equatable, Sendable {
    /// 机体各轴在世界坐标下的单位向量。
    public var right: Vec3
    public var up: Vec3
    public var forward: Vec3

    public init(right: Vec3, up: Vec3, forward: Vec3) {
        self.right = right
        self.up = up
        self.forward = forward
    }

    /// 由前向与上向构造正交基（Gram-Schmidt）。
    public init(forward rawForward: Vec3, up rawUp: Vec3) {
        let f = rawForward.normalized
        // 右手系：right = forward × up
        var r = f.cross(rawUp)
        if r.lengthSquared < 1e-10 {
            // 上向量与前向量平行时，退化到任意垂直方向。
            r = f.cross(Vec3(1, 0, 0))
            if r.lengthSquared < 1e-10 { r = f.cross(Vec3(0, 0, 1)) }
        }
        self.right = r.normalized
        self.up = f.cross(self.right).normalized
        self.forward = f
    }

    public static let identity = BodyFrame(right: Vec3(1, 0, 0), up: Vec3(0, 1, 0), forward: Vec3(0, 0, -1))

    /// 机体坐标 → 世界坐标。
    @inlinable public func toWorld(_ v: Vec3) -> Vec3 {
        right * v.x + up * v.y + forward * v.z
    }

    /// 世界坐标 → 机体坐标。
    @inlinable public func toBody(_ v: Vec3) -> Vec3 {
        Vec3(v * right, v * up, v * forward)
    }

    /// 由四元数构造机体姿态。
    public init(quaternion q: Quat) {
        self.init(forward: q.forward, up: q.up)
    }

}

// MARK: - 四元数

/// 单位四元数（w, x, y, z），表示从机体到世界的旋转。
public struct Quat: Equatable, Sendable {
    public var w: Float
    public var x: Float
    public var y: Float
    public var z: Float

    public init(_ w: Float = 1, _ x: Float = 0, _ y: Float = 0, _ z: Float = 0) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    public static let identity = Quat(1, 0, 0, 0)

    @inlinable public var length: Float { (w * w + x * x + y * y + z * z).squareRoot() }

    @inlinable public var normalized: Quat {
        let l = length
        guard l > 1e-8 else { return .identity }
        return Quat(w / l, x / l, y / l, z / l)
    }

    /// 从前向与上向构造四元数（罗德里格斯向量法）。
    public init(forward rawForward: Vec3, up rawUp: Vec3) {
        let f = rawForward.normalized
        var u = rawUp.normalized
        // 正交化
        u = (u - f * (f * u)).normalized
        if u.lengthSquared < 1e-10 {
            u = f.cross(Vec3(0, 1, 0))
            if u.lengthSquared < 1e-10 { u = f.cross(Vec3(1, 0, 0)) }
            u = u.normalized
        }
        let r = f.cross(u)  // 右手系：right = forward × up
        // 旋转矩阵列：right, up, forward
        let m00 = r.x, m01 = u.x, m02 = f.x
        let m10 = r.y, m11 = u.y, m12 = f.y
        let m20 = r.z, m21 = u.z, m22 = f.z
        // 矩阵 → 四元数（Shepperd 方法）
        let trace = m00 + m11 + m22
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            w = 0.25 * s
            x = (m21 - m12) / s
            y = (m02 - m20) / s
            z = (m10 - m01) / s
        } else if m00 > m11, m00 > m22 {
            let s = (1 + m00 - m11 - m22).squareRoot() * 2
            w = (m21 - m12) / s
            x = 0.25 * s
            y = (m01 + m10) / s
            z = (m02 + m20) / s
        } else if m11 > m22 {
            let s = (1 + m11 - m00 - m22).squareRoot() * 2
            w = (m02 - m20) / s
            x = (m01 + m10) / s
            y = 0.25 * s
            z = (m12 + m21) / s
        } else {
            let s = (1 + m22 - m00 - m11).squareRoot() * 2
            w = (m10 - m01) / s
            x = (m02 + m20) / s
            y = (m12 + m21) / s
            z = 0.25 * s
        }
        let n = normalized
        self = n
    }

    /// 由绕轴旋转的角度构造（轴需为单位向量）。
    public init(axis: Vec3, angle: Float) {
        let a = axis.normalized
        let h = angle * 0.5
        let s = sin(h)
        self = Quat(cos(h), a.x * s, a.y * s, a.z * s).normalized
    }

    /// 机体坐标 → 世界坐标。
    @inlinable public func toWorld(_ v: Vec3) -> Vec3 { rotated(v) }

    /// 世界坐标 → 机体坐标。
    @inlinable public func toBody(_ v: Vec3) -> Vec3 { Quat.conjugate(self).rotated(v) }

    @inlinable public var forward: Vec3 { Vec3(0, 0, -1).rotated(by: self) }

    @inlinable public var up: Vec3 { Vec3(0, 1, 0).rotated(by: self) }

    @inlinable public var right: Vec3 { Vec3(1, 0, 0).rotated(by: self) }

    public static func * (a: Quat, b: Quat) -> Quat {
        Quat(
            a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
            a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w
        )
    }

    /// 四元数积分（机体角速度）：q' = exp(½·ω·dt) ⊗ q。
    ///
    /// 用指数映射而不是一阶欧拉：欧拉在 dt 较大时误差明显
    /// （转 1 rad 会算成 0.927 rad），指数映射是精确的。
    @inlinable public func integrated(byBodyAngularVelocity omega: Vec3, dt: Float) -> Quat {
        let theta = omega.length
        guard theta > 1e-9, dt != 0 else {
            // 角速度极小时退化成欧拉步
            let dq = Quat(0, omega.x, omega.y, omega.z) * self
            return Quat(w + dq.w * 0.5 * dt,
                        x + dq.x * 0.5 * dt,
                        y + dq.y * 0.5 * dt,
                        z + dq.z * 0.5 * dt).normalized
        }
        let angle = theta * dt
        let half = angle * 0.5
        let scale = sin(half) / theta
        let delta = Quat(cos(half), omega.x * scale, omega.y * scale, omega.z * scale)
        return (delta * self).normalized
    }

    /// 从四元数取机体角速度（与 integrated 互逆）。
    @inlinable public func bodyAngularVelocity(fromConjugateRate wq: Quat) -> Vec3 {
        let dq = wq * Quat.conjugate(self)
        return Vec3(dq.x * 2, dq.y * 2, dq.z * 2)
    }

    @inlinable public static func conjugate(_ q: Quat) -> Quat { Quat(q.w, -q.x, -q.y, -q.z) }

    /// 旋转向量。
    @inlinable public func rotated(_ v: Vec3) -> Vec3 {
        let qv = Quat(0, v.x, v.y, v.z)
        let r = self * qv * Quat.conjugate(self)
        return Vec3(r.x, r.y, r.z)
    }
}

extension Vec3 {
    /// 用四元数旋转向量。
    @inlinable public func rotated(by q: Quat) -> Vec3 { q.rotated(self) }
}
